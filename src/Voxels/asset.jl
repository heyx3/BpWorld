###############################
##   Layer data definition   ##
###############################

"The data definition for a specific voxel material."
struct LayerData
    # The fragment shader file.
    # The vertex shader will always be "voxels/meshed.vert"
    frag_shader_path::AbstractString

    # The textures used by this voxel asset.
    # Each file name is mapped to a sampler2D uniform in the fragment shader.
    # This uniform is automatically generated, for your convenience.
    textures::Dict{AbstractString, AbstractString}

    # The default sampler is for usual 3D surfaces:
    #    repeat, linear filtering, mipmaps, anisotropy based on graphics settings.
    # You can change the sampler to use here.
    # The textures are indexed by their uniform name here, not their file-name.
    samplers::Dict{AbstractString, Sampler{2}}
    #TODO: Replace 'samplers' with a larger set of settings, like "include mips?"

    # The fragment shader to use for a depth-only pass.
    # This shader file should be in a specific "assets" sub-folder.
    # Defaults to "basic.frag".
    depth_pass::AbstractString


    # Any #defines you want to add in the fragment shader.
    # The keys are the token names, and the values are the token values.
    # E.x. the value "ABC" => "1" translates into "#define ABC 1".
    preprocessor_defines::Dict{AbstractString, AbstractString}

    # This constructor handles 'nothing' values for each field, for StructTypes deserialization.
    LayerData(frag_shader_path, textures, samplers, depth_pass, preprocessor_defines) = new(
        isnothing(frag_shader_path) ?
            error("Field 'frag_shader_path' must be set for a voxel asset!") : #TODO: Default to an 'error' shader.
            frag_shader_path,
        isnothing(textures) ?
            Dict{AbstractString, AbstractString}() :
            textures,
        isnothing(samplers) ?
            Dict{AbstractString, Sampler{2}}() :
            samplers,
        isnothing(depth_pass) ?
            "basic.frag" :
            depth_pass,
        isnothing(preprocessor_defines) ?
            Dict{AbstractString, AbstractString}() :
            preprocessor_defines
    )
end

# Serialization:
StructTypes.StructType(::Type{LayerData}) = StructTypes.UnorderedStruct()


#################
##   Shaders   ##
#################

"
Voxels have multiple shader programs that can render them,
    under different circumstances.
"
struct VoxelPrograms
    preview::Program
    meshed::Program
end
function Base.close(vp::VoxelPrograms)
    close(vp.preview)
    close(vp.meshed)
end


"
Generates a voxel layer's shaders, given a custom fragment shader.
"
function make_voxel_program(fragment_shader::AbstractString,
                            frag_shader_header::AbstractString = "",
                            builtin_shaders_header::AbstractString = ""
                           )::VoxelPrograms
    vertex_shader_preview::AbstractString = open(
        io -> read(io, String),
        joinpath(VOXELS_ASSETS_PATH, "preview.vert"),
        "r"
    )
    vertex_shader_meshed::AbstractString = open(
        io -> read(io, String),
        joinpath(VOXELS_ASSETS_PATH, "meshed.vert"),
        "r"
    )
    geom_shader_preview::AbstractString = open(
        io -> read(io, String),
        joinpath(VOXELS_ASSETS_PATH, "preview.geom"),
        "r"
    )

    # Pre-process each shader file.
    context = ""
    try
        context = "preview vertex"
        vertex_shader_preview = process_shader_contents(vertex_shader_preview,
                                                        builtin_shaders_header)
        context = "meshed vertex"
        vertex_shader_meshed = process_shader_contents(vertex_shader_meshed,
                                                       builtin_shaders_header)

        context = "geometry"
        geom_shader_preview = process_shader_contents(geom_shader_preview,
                                                      builtin_shaders_header)

        context = "fragment"
        fragment_shader = process_shader_contents(fragment_shader, frag_shader_header)
    catch e
        error("Failed to preprocess ", context, " shader. ", e)
    end

    # Finally, compile and return.
    return VoxelPrograms(
        Program(
            vertex_shader_preview, fragment_shader
            ;
            geom_shader = geom_shader_preview,
            flexible_mode = true
        ),
        Program(
            vertex_shader_meshed, fragment_shader
            ;
            flexible_mode = true
        )
    )
end


"Assets for rendering voxel layers in a depth-only pass"
mutable struct LayerDepthRenderer
    by_file::Dict{AbstractString, VoxelPrograms}
    #TODO: Let depth renderers sample from textures (e.x. for transparent-cutout)
end
function Base.close(ldr::LayerDepthRenderer)
    for vp::VoxelPrograms in values(ldr.by_file)
        close(vp)
    end
    empty!(ldr.by_file)
end

const DEPTH_ONLY_PASSES_FOLDER = joinpath(VOXELS_ASSETS_PATH, "DepthOnly")

"Loads all depth-only passes specified in `DEPTH_ONLY_PASSES_FOLDER`"
function LayerDepthRenderer()
    return LayerDepthRenderer(Dict(map(readdir(DEPTH_ONLY_PASSES_FOLDER)) do file
        full_path = joinpath(DEPTH_ONLY_PASSES_FOLDER, file)
        file_contents = open(io -> read(io, String), full_path, "r")
        return file => make_voxel_program(file_contents,
                                          "#include <voxels/common_frag.shader>")
    end))
end


#########################
##   Layer rendering   ##
#########################

"A renderable voxel material."
mutable struct LayerRenderer
    shader_program::VoxelPrograms
    shader_program_depth_only_name::AbstractString

    # Each texture is mapped to its uniform name.
    textures::Dict{AbstractString, Texture}
end
function LayerRenderer(data::LayerData, depth_only_programs::LayerDepthRenderer)
    # Generate the shader header.
    defines = sprint() do io::IO
        for (name, value) in data.preprocessor_defines
            print(io, "#define ", name, " ", value, "\n")
        end
    end
    fragment_header = sprint() do io::IO
        print(io, defines, "\n")
        for u_name in values(data.textures)
            print(io, "uniform sampler2D ", u_name, ";\n")
        end
        print(io, "#include <voxels/common_frag.shader>")
    end
    # Load the shader.
    fragment_path = joinpath(VOXELS_ASSETS_PATH, data.frag_shader_path)
    if !isfile(fragment_path)
        error("Fragment shader file doesn't exist: '", fragment_path, "'")
    end
    fragment_shader = open(io -> read(io, String), fragment_path, "r")
    # Compile the Programs.
    programs = make_voxel_program(fragment_shader, fragment_header, defines)

    textures = Dict(Iterators.map(data.textures) do (path, uniform_name)
        # Check that the file exists.
        full_path = joinpath(VOXELS_ASSETS_PATH, path)
        if !isfile(full_path)
            error("Texture file not found '", full_path, "'")
        end

        # Pick a sampler for this texture.
        sampler = get(data.samplers, uniform_name, Sampler{2}(
            wrapping = WrapModes.repeat,
            pixel_filter = PixelFilters.smooth,
            mip_filter = PixelFilters.smooth
        ))

        # Load the pixels as 8-bit RGB.
        #TODO: Allow for customization of the format
        tex = try
            load_tex(full_path, vRGBu8,
                     SimpleFormat(FormatTypes.normalized_uint,
                                  SimpleFormatComponents.RGB,
                                  SimpleFormatBitDepths.B8),
                     sampler = sampler)
        catch e
            #TODO: Return an error texture instead of a hard crash
            error("Unable to load texture '", full_path, "': ", e)
        end

        return uniform_name => tex
    end)

    if !(haskey(depth_only_programs.by_file, data.depth_pass))
        error("Voxel layer '", data.frag_shader_path,
              "' lists a nonexistent depth-only pass, '", data.depth_pass, "'")
    end

    return LayerRenderer(programs, data.depth_pass, textures)
end

function Base.close(a::LayerRenderer)
    close(a.shader_program.preview)
    close(a.shader_program.meshed)
    for tex in values(a.textures)
        close(tex)
    end
    empty!(a.textures)

    # Don't close the depth-only program, as that can be shared across voxels.
end


##   Helpers to set up rendering for the various voxel shader programs   ##

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
function prepare_voxel_gbuffer_render( prog::Program, asset::LayerRenderer,
                                       cam::Cam3D, elapsed_seconds::Float32
                                     )
    set_uniform(prog, "u_camPos", cam.pos)
    set_uniform(prog, "u_camForward", cam.forward)
    set_uniform(prog, "u_camUp", cam.up)
    set_uniform(prog, "u_totalSeconds", elapsed_seconds)
    for (u_name, texture) in asset.textures
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
function render_voxels_depth_only( mesh::Mesh, asset::LayerRenderer,
                                   depth_renderers::LayerDepthRenderer,
                                   offset::v3f, scale::v3f,
                                   cam::Cam3D, camera_mat_viewproj::fmat4
                                 )
    prog::Program = depth_renderers.by_file[asset.shader_program_depth_only_name].meshed
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    render_mesh(mesh, prog)
end
"Renders a voxel layer with depth-only, using the 'preview' shader program"
function render_voxels_depth_only( voxels::Texture, layer_idx::Integer,
                                   asset::LayerRenderer,
                                   depth_renderers::LayerDepthRenderer,
                                   offset::v3f, scale::v3f,
                                   cam::Cam3D, camera_mat_viewproj::fmat4
                                 )
    prog::Program = depth_renderers.by_file[asset.shader_program_depth_only_name].preview
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
function render_voxels( mesh::Mesh, asset::LayerRenderer,
                        offset::v3f, scale::v3f, camera::Cam3D,
                        total_elapsed_seconds::Float32,
                        camera_mat_viewproj::fmat4
                      )
    prog::Program = asset.shader_program.meshed
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    prepare_voxel_gbuffer_render(prog, asset, camera, total_elapsed_seconds)

    # Render, and take care of texture views.
    for texture in values(asset.textures)
        view_activate(get_view(texture))
    end
    render_mesh(mesh, prog)
    for texture in values(asset.textures)
        view_deactivate(get_view(texture))
    end
end
"Renders a voxel layer, using the 'preview' shader program"
function render_voxels( voxels::Texture, layer_idx::Integer,
                        asset::LayerRenderer,
                        offset::v3f, scale::v3f, camera::Cam3D,
                        total_elapsed_seconds::Float32,
                        camera_mat_viewproj::fmat4
                      )
    prog::Program = asset.shader_program.preview
    prepare_voxel_render(prog, offset, scale, camera_mat_viewproj)
    prepare_voxel_gbuffer_render(prog, asset, camera, total_elapsed_seconds)
    prepare_voxel_preview_render(prog, voxels, layer_idx)

    # Render, and take care of texture views.
    for texture in values(asset.textures)
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
    for texture in values(asset.textures)
        view_deactivate(get_view(texture))
    end
    view_deactivate(voxels)
end