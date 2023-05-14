#TODO: Cache textures like we do for materials

###################
##   Materials   ##
###################

"
A set of shaders for rendering a single voxel layer.

Provides 'meshed' and 'preview' versions of the shaders
   ('preview' is for the less efficient rendering before meshing is complete).

Provides 'depth' (for depth-prepass) and 'deferred' (for G-buffer pass) versions of the shaders.
"
struct LayerMaterial
    depth_preview::Program
    deferred_preview::Program
    
    depth_meshed::Program
    deferred_meshed::Program
    
    # Each texture is mapped to its uniform name.
    textures::Dict{AbstractString, Texture}
end

function Base.close(m::LayerMaterial)
    close(m.depth_preview)
    close(m.deferred_preview)
    close(m.depth_meshed)
    close(m.deferred_meshed)

    close.(values(m.textures))
end


"Relative path from the usual shader include folder to the special builtin shader folder"
const BUILTIN_SHADERS_INCLUDE_PATH = "../assets/voxels"

"Generates a layer material, given the user's fragment shader"
function LayerMaterial(data::LayerData)::LayerMaterial
    fragment_shader_body = read(joinpath(VOXEL_LAYERS_PATH,
                                         data.frag_shader_path),
                                String)

    # If an exception is thrown, everything up to that point needs to be cleaned up.
    resources = Resource[ ]
    try
        # Vertex/geometry shaders depend on whether the layer is meshed yet.
        vert_preview = """
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/utils.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/vert_geom/preview.vert>
        """
        vert_meshed = """
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/utils.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/vert_geom/meshed.vert>
        """
        geom_preview = """
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/utils.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/vert_geom/preview.geom>
        """

        # Generate declarations from the user data.
        frag_defines = sprint() do io::IO
            for (name, value) in data.preprocessor_defines
                print(io, "#define ", name, " ", value, "\n")
            end
            for tex_data::LayerTexture in values(data.textures)
                print(io, "uniform sampler2D ", tex_data.code_name, ";\n")
            end
        end

        # Fragment shaders depend on which pass is being rendered.
        frag_deferred = """
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/utils.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/frag/input.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/frag/output_deferred.shader>

            $frag_defines

            #line 1
            $fragment_shader_body
        """
        frag_depth = """
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/utils.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/frag/input.shader>
            #include <$BUILTIN_SHADERS_INCLUDE_PATH/frag/output_depth.shader>

            $frag_defines

            #line 1
            $fragment_shader_body
        """

        # Run our own preprocessor on the code.
        (vert_preview, vert_meshed, geom_preview, frag_deferred, frag_depth) =
            process_shader_contents.((vert_preview, vert_meshed, geom_preview,
                                    frag_deferred, frag_depth))

        # Generate the Programs.
        prog_preview_depth = Program(vert_preview, frag_depth,
                                     geom_shader=geom_preview)
        push!(resources, prog_preview_depth)
        prog_preview_deferred = Program(vert_preview, frag_deferred,
                                        geom_shader=geom_preview)
        push!(resources, prog_preview_deferred)
        prog_meshed_depth = Program(vert_meshed, frag_depth)
        push!(resources, prog_meshed_depth)
        prog_meshed_deferred = Program(vert_meshed, frag_deferred)
        push!(resources, prog_meshed_deferred)

        # Load the textures.
        textures = Dict(Iterators.map(data.textures) do (path, tex_data)
            # Check that the file exists.
            full_path = joinpath(VOXEL_LAYERS_PATH, path)
            if !isfile(full_path)
                error("Texture file not found '", full_path, "'")
            end

            # Pick a sampler for this texture.
            sampler = exists(tex_data.sampler) ? tex_data.sampler : DEFAULT_SAMPLER

            # Load the pixels.
            tex = try
                load_tex(full_path, vRGBu8,
                        SimpleFormat(FormatTypes.normalized_uint,
                                    tex_data.channels,
                                    SimpleFormatBitDepths.B8),
                        sampler = sampler,
                        use_mips=tex_data.use_mips)
            catch e
                error("Unable to load texture '", full_path, "': ", sprint(showerror, e))
            end
            push!(resources, tex)

            return tex_data.code_name => tex
        end)

        return LayerMaterial(
            prog_preview_depth,
            prog_preview_deferred,
            prog_meshed_depth,
            prog_meshed_deferred,
            textures
        )
    catch e
        close.(resources)
        rethrow()
    end
end


#########################
##   Layer rendering   ##
#########################

const DEFAULT_SAMPLER = Sampler{2}(
    wrapping = WrapModes.repeat,
    pixel_filter = PixelFilters.smooth,
    mip_filter = PixelFilters.smooth
)

##   Helpers to set up rendering for the various voxel shader programs   ##

#TODO: Make basically all uniforms available in all shaders (e.x. voxel grid in deferred)

function prepare_voxel_render( prog::Program,
                               offset::v3f, scale::v3f,
                               cam_mat_viewproj::fmat4
                             )
    # Set render state.
    set_depth_writes(true)
    set_depth_test(ValueTests.LessThan)
    # Disable culling until I can make sure all triangles are oriented correctly.
    #TODO: Figure out voxel triangle orientation.
    set_culling(FaceCullModes.Off)

    set_uniform(prog, "u_world_offset", offset)
    set_uniform(prog, "u_world_scale", scale)
    set_uniform(prog, "u_mat_viewproj", cam_mat_viewproj)
end
function prepare_voxel_gbuffer_render( prog::Program, material::LayerMaterial,
                                       cam::Cam3D, elapsed_seconds::Float32
                                     )
    set_uniform(prog, "u_camPos", cam.pos)
    set_uniform(prog, "u_camForward", cam.forward)
    set_uniform(prog, "u_camUp", cam.up)
    set_uniform(prog, "u_totalSeconds", elapsed_seconds)
    for (u_name, texture) in material.textures
        set_uniform(prog, u_name, texture)
    end
end
function prepare_voxel_preview_render(prog::Program, voxel_grid::Texture, layer_idx::Integer)
    set_uniform(prog, "u_nVoxels", convert(v3u, voxel_grid.size))
    set_uniform(prog, "u_voxelGrid", voxel_grid)
    set_uniform(prog, "u_voxelLayer", convert(UInt32, layer_idx))
end


##   Public interface for rendering voxels   ##

"Renders a voxel layer with depth-only, using the 'meshed' shader program"
function render_voxels_depth_only(mesh::Mesh, material::LayerMaterial,
                                  offset::v3f, scale::v3f,
                                  cam::Cam3D, camera_mat_viewproj::fmat4
                                 )
    prog::Program = material.depth_meshed
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    render_mesh(mesh, prog)
end
"Renders a voxel layer with depth-only, using the 'preview' shader program"
function render_voxels_depth_only( voxels::Texture, layer_idx::Integer,
                                   material::LayerMaterial,
                                   offset::v3f, scale::v3f,
                                   cam::Cam3D, camera_mat_viewproj::fmat4
                                 )
    prog::Program = material.depth_preview
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    prepare_voxel_preview_render(prog, voxels, layer_idx)

    # Render.
    # This is just for previews, so excessive texture deactivation/reactivation within a frame
    #    is less painful than the mental complication of attempting to optimize that away.
    view_activate(voxels)
    render_mesh(
        get_resources().empty_mesh, prog
        ;
        shape = PrimitiveTypes.point,
        indexed_params = nothing,
        elements = Box_minsize(
            UInt32(1),
            UInt32(prod(voxels.size))
        )
    )
    view_deactivate(voxels)
end

"Renders a voxel layer, using the 'meshed' shader program"
function render_voxels( mesh::Mesh, material::LayerMaterial,
                        offset::v3f, scale::v3f, camera::Cam3D,
                        total_elapsed_seconds::Float32,
                        camera_mat_viewproj::fmat4
                      )
    prog::Program = material.deferred_meshed
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    prepare_voxel_gbuffer_render(prog, material, camera, total_elapsed_seconds)

    # Render, and take care of texture views.
    for texture in values(material.textures)
        view_activate(get_view(texture))
    end
    render_mesh(mesh, prog)
    for texture in values(material.textures)
        view_deactivate(get_view(texture))
    end
end
"Renders a voxel layer, using the 'preview' shader program"
function render_voxels( voxels::Texture, layer_idx::Integer,
                        material::LayerMaterial,
                        offset::v3f, scale::v3f, camera::Cam3D,
                        total_elapsed_seconds::Float32,
                        camera_mat_viewproj::fmat4
                      )
    prog::Program = material.deferred_preview
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    prepare_voxel_gbuffer_render(prog, material, camera, total_elapsed_seconds)
    prepare_voxel_preview_render(prog, voxels, layer_idx)

    # Render, and take care of texture views.
    for texture in values(material.textures)
        view_activate(get_view(texture))
    end
    view_activate(voxels)
    render_mesh(
        get_resources().empty_mesh, prog
        ;
        shape = PrimitiveTypes.point,
        indexed_params = nothing,
        elements = Box_minsize(
            UInt32(1),
            UInt32(prod(voxels.size))
        )
    )
    for texture in values(material.textures)
        view_deactivate(get_view(texture))
    end
    view_deactivate(voxels)
end