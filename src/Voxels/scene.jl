"A set of voxel layers, and any active operations being done with them"
mutable struct Scene
    grid::VoxelGrid
    grid_tex3d::GL.Texture # Red-only, 8-bit uint
    world_scale::v3f

    # There is an ongoing Task to compute the voxels, and then each layer's mesh.
    is_finished_setting_up::Bool
    layer_meshes::Vector{Tuple{AbstractString,
                               Optional{Tuple{GL.Buffer, GL.Buffer, GL.Mesh}}}}
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

function Scene(grid_size::v3i,
               grid_generator::Generation.AbstractVoxelGenerator,
               layer_names::AbstractVector{<:AbstractString},
               world_scale::v3f
              )::Scene
    grid::VoxelGrid = fill(zero(VoxelElement),
                           grid_size...)

    # On a separate task, generate voxels and then the meshes.
    mesher = VoxelMesher()
    meshing_channel_to_main = Channel{Int}(2)
    meshing_channel_to_worker = Channel{Bool}(2)
    voxel_task = @async begin
        Generation.generate!(grid, grid_generator, true)
        put!(meshing_channel_to_main, 0)

        #TODO: Use one big buffer for the voxel data, signal back to the main thread after every slice

        for i in 1:length(layer_names)
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
            sampler = TexSampler{3}(
                wrapping = WrapModes.clamp,
                pixel_filter = PixelFilters.rough,
                mip_filter = nothing
            )
        ),

        world_scale,

        false,
        map(i -> (layer_names[i], nothing),
            1:length(layer_names)),
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
    close.(Iterators.flatten(m[2] for m in scene.layer_meshes if exists(m[2])))
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
            @bpworld_assert(!scene.is_finished_setting_up)
            @bpworld_assert(finished_idx <= length(scene.layer_meshes))
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
                        MeshIndexData(inds, eltype(scene.mesher.index_buffer))
                    )
                    let element = scene.layer_meshes[finished_idx]
                        @set! element[2] = (verts, inds, mesh)
                        scene.layer_meshes[finished_idx] = element
                    end
                end
            end

            put!(scene.meshing_channel_to_worker, true)

            # If this was the last layer, we're finished.
            if finished_idx == length(scene.layer_meshes)
                scene.is_finished_setting_up = true
            end
        end
    # If the task is still running and Julia only has one thread,
    #    we need to manually yield our time to give the task a chance.
    elseif Threads.nthreads() == 1
        yield()
    end
end

function render(scene::Scene,
                mat_viewproj::fmat4, elapsed_seconds::Float32,
                material_cache::RendererCache)
    for i::Int in 1:length(scene.layer_meshes)
        material = get_material!(material_cache, scene.layer_meshes[i][1])
        if exists(scene.layer_meshes[i][2])
            render_voxels(scene.layer_meshes[i][2][3], material,
                          zero(v3f), scene.world_scale,
                          elapsed_seconds, mat_viewproj)
        else
            render_voxels(scene.grid_tex3d, i, material,
                          zero(v3f), scene.world_scale,
                          elapsed_seconds, mat_viewproj)
        end
    end

    return nothing
end
function render_depth_only(scene::Scene,
                           mat_viewproj::fmat4,
                           material_cache::RendererCache)
    for i::Int in 1:length(scene.layer_meshes)
        material = get_material!(material_cache, scene.layer_meshes[i][1])
        if exists(scene.layer_meshes[i][2])
            render_voxels_depth_only(scene.layer_meshes[i][2][3], material,
                                     zero(v3f), scene.world_scale,
                                     mat_viewproj)
        else
            render_voxels_depth_only(scene.grid_tex3d, i, material,
                                     zero(v3f), scene.world_scale,
                                     mat_viewproj)
        end
    end
end