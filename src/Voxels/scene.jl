"A set of voxel layers, and any active operations being done with them"
mutable struct Scene
    grid::VoxelGrid
    grid_tex3d::GL.Texture # Red-only, 8-bit uint
    world_scale::v3f

    layers::Vector{LayerRenderer}

    # In depth-only rendering, voxels can share their materials.
    # So, voxel layers are sorted by material before a depth-only pass.
    buffer_sorted_voxel_layers::Vector{Tuple{LayerRenderer, GL.Program,
                                             Union{GL.Mesh, Tuple{GL.Texture, Int}}}}

    # There is an ongoing Task to compute the voxels, and then each layer's mesh.
    layer_meshes::Vector{Optional{Tuple{GL.Buffer, GL.Buffer, GL.Mesh}}}
    mesher::VoxelMesher
    voxel_task::Task
    meshing_channel_to_main::Channel{Int} # Worker thread sends back the index of each meshed layer
                                          #    as it's completed.
                                          # But first, sends 0 after the voxel grid is generated.
    meshing_channel_to_worker::Channel{Bool} # Main thread sends an acknowledgement
                                             #    of each meshed layer, after uploading it.
                                             # The initial 0 value shouldn't be acknowledged.
                                             # Send 'true' to acknowledge, 'false' to kill the task.
end

function Scene(grid_size::v3i, grid_generator::Generation.AbstractVoxelGenerator,
               world_scale::v3f,
               assets::Vector{LayerRenderer}
              )::Scene
    grid::VoxelGrid = fill(zero(VoxelElement),
                           grid_size...)

    #TODO: Check the range of voxel outputs of the generator; make sure they don't exceed the number of assets

    # On a separate task, generate voxels and then the meshes.
    mesher = VoxelMesher()
    meshing_channel_to_main = Channel{Int}(2)
    meshing_channel_to_worker = Channel{Bool}(2)
    voxel_task = @async begin
        Generation.generate!(grid, grid_generator, true)
        put!(meshing_channel_to_main, 0)

        #TODO: Use one big buffer for the voxel data, signal back to the main thread after every slice

        for i in 1:length(assets)
            calculate_mesh(grid, UInt8(i), mesher)
            put!(meshing_channel_to_main, i)

            should_continue::Bool = take!(meshing_channel_to_worker)
            if !should_continue
                break
            end
        end
    end

    return Scene(
        grid,
        Texture(
            SimpleFormat(
                FormatTypes.uint,
                SimpleFormatComponents.R,
                SimpleFormatBitDepths.B8
            ),
            grid
            ;
            n_mips = 1,
            sampler = Sampler{3}(
                wrapping = WrapModes.clamp,
                pixel_filter = PixelFilters.rough,
                mip_filter = nothing
            )
        ),

        world_scale,

        assets,
        Vector{Tuple{LayerRenderer, GL.Program, Union{GL.Mesh, Tuple{GL.Texture, Int}}}}(),

        fill(nothing, length(assets)),
        mesher,
        voxel_task,
        meshing_channel_to_main,
        meshing_channel_to_worker
    )
end

function Base.close(scene::Scene)
    # Close the worker task.
    put!(scene.meshing_channel_to_worker, false)
    wait(scene.voxel_task)
    close(scene.meshing_channel_to_worker)
    close(scene.meshing_channel_to_main)

    # Clean up owned GL assets.
    close(scene.grid_tex3d)
    for data in scene.layer_meshes
        if exists(data)
            for resource in data
                close(resource)
            end
        end
    end

    # Note that the voxel layer assets are not owned by the scene.
end

function update(scene::Scene, delta_seconds::Float32)
    # Check if the voxel worker task has an update.
    if isready(scene.meshing_channel_to_main)
        finished_idx::Int = take!(scene.meshing_channel_to_main)
        # Did the task just finish initial voxel generation?
        if finished_idx == 0
            println("Voxel scene is completed! Uploading into texture...")
            @time set_tex_color(scene.grid_tex3d, scene.grid)
        # Otherwise, it finished meshing a voxel layer.
        else
            @bpworld_assert(finished_idx <= length(scene.layers))
            println("Layer ", finished_idx, " is done meshing")

            # Don't bother generating an empty mesh.
            if scene.mesher.n_indices > 0
                @time begin
                    verts = Buffer(false, @view scene.mesher.vertex_buffer[1:scene.mesher.n_vertices])
                    inds = Buffer(false, @view scene.mesher.index_buffer[1:scene.mesher.n_indices])
                    mesh = Mesh(
                        PrimitiveTypes.triangle,
                        [ VertexDataSource(verts, sizeof(VoxelVertex)) ],
                        voxel_vertex_layout(1),
                        (inds, eltype(scene.mesher.index_buffer))
                    )
                    scene.layer_meshes[finished_idx] = (verts, inds, mesh)
                end
            end

            put!(scene.meshing_channel_to_worker, true)
        end
    # If the task is still running and Julia only has one thread,
    #    we need to manually yield our time to give the task a chance.
    elseif Threads.nthreads() == 1
        yield()
    end
end

function render(scene::Scene, cam::Cam3D, mat_cam_viewproj::fmat4, elapsed_seconds::Float32)
    for i::Int in 1:length(scene.layers)
        if exists(scene.layer_meshes[i])
            render_voxels(scene.layer_meshes[i][3],
                          scene.layers[i],
                          zero(v3f), scene.world_scale,
                          cam, elapsed_seconds, mat_cam_viewproj)
        else
            render_voxels(scene.grid_tex3d, i,
                          scene.layers[i],
                          zero(v3f), scene.world_scale,
                          cam, elapsed_seconds, mat_cam_viewproj)
        end
    end

    return nothing
end
function render_depth_only(scene::Scene, renderers::LayerDepthRenderer,
                           cam::Cam3D, mat_cam_viewproj::fmat4)
    # Sort the voxel layers by their depth-only shader, to minimize driver overhead.
    # Assign each entry some data related to rendering.
    voxel_layers::Vector = scene.buffer_sorted_voxel_layers
    empty!(voxel_layers)
    for (layer_idx, (layer, resources)) in enumerate(zip(scene.layers, scene.layer_meshes))
        prog = renderers.by_file[layer.shader_program_depth_only_name]
        # Check whether or not we'll be using the preview shader.
        if exists(resources)
            (buf1, buf2, mesh::GL.Mesh) = resources
            push!(voxel_layers, (layer, prog.meshed, mesh))
        else
            push!(voxel_layers, (layer, prog.preview, (scene.grid_tex3d, layer_idx)))
        end
    end
    sort!(voxel_layers, by=(data -> GL.gl_type(GL.get_ogl_handle(data[2]))))

    for (layer, prog, data) in voxel_layers
        if data isa GL.Mesh
            render_voxels_depth_only(data, layer, renderers,
                                    zero(v3f), scene.world_scale,
                                    cam, mat_cam_viewproj)
        else
            render_voxels_depth_only(data..., layer, renderers,
                                     zero(v3f), scene.world_scale,
                                     cam, mat_cam_viewproj)
        end
    end
end