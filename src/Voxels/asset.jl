###############################
##   Layer data definition   ##
###############################

"The data definition for a specific voxel material."
struct LayerData
    # The fragment shader file.
    # The vertex shader will always be "voxels/voxels.vert"
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

"Generates a voxel shader Program with the given fragment shader"
function make_voxel_program(fragment_shader::AbstractString,
                            frag_shader_header::AbstractString = "",
                            vert_shader_header::AbstractString = ""
                           )::Program
    #TODO: A Context service that pre-loads the voxel vertex shader and anything else that's needed
    vertex_shader::AbstractString = open(io -> read(io, String),
                                         joinpath(VOXELS_ASSETS_PATH, "voxels.vert"),
                                         "r")

    context = ""
    try
        context = "vertex"
        vertex_shader = process_shader_contents(vertex_shader, vert_shader_header)
        context = "fragment"
        fragment_shader = process_shader_contents(fragment_shader, frag_shader_header)
    catch e
        error("Failed to preprocess ", context, " shader. ", e)
    end

    return Program(vertex_shader, fragment_shader; flexible_mode=true)
end


"Assets for rendering voxel layers in a depth-only pass"
mutable struct LayerDepthRenderer
    by_file::Dict{AbstractString, Program}
end
function Base.close(ldr::LayerDepthRenderer)
    for prog::Program in values(ldr.by_file)
        close(prog)
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
                                          "#include <voxels/common.shader>")
    end))
end


#########################
##   Layer rendering   ##
#########################

"A renderable voxel material."
mutable struct LayerRenderer
    shader_program::Program
    shader_program_depth_only::Program

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
        print(io, "#include <voxels/common.shader>")
    end
    # Load the shader.
    fragment_path = joinpath(VOXELS_ASSETS_PATH, data.frag_shader_path)
    if !isfile(fragment_path)
        error("Fragment shader file doesn't exist: '", fragment_path, "'")
    end
    fragment_shader = open(io -> read(io, String), fragment_path, "r")
    # Compile the Program.
    program = make_voxel_program(fragment_shader, fragment_header,
                                 defines)

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

    return LayerRenderer(program,
                         depth_only_programs.by_file[data.depth_pass],
                         textures)
end

function Base.close(a::LayerRenderer)
    close(a.shader_program)
    for tex in values(a.textures)
        close(tex)
    end
    empty!(a.textures)

    # Don't close the depth-only program, as that can be shared across voxels.
end


function render_voxels_depth_only( mesh::Mesh, asset::LayerRenderer,
                                   offset::v3f, scale::v3f,
                                   cam::Cam3D, camera_mat_viewproj::fmat4)
    # Set render state.
    set_depth_writes(true)
    set_depth_test(ValueTests.LessThan)
    # Disable culling until I can make sure all triangles are oriented correctly.
    #TODO: Figure out voxel triangle orientation.
    set_culling(FaceCullModes.Off)

    # Set uniforms.
    set_uniform(asset.shader_program_depth_only, "u_world_offset", offset)
    set_uniform(asset.shader_program_depth_only, "u_world_scale", scale)
    set_uniform(asset.shader_program_depth_only, "u_mat_viewproj", camera_mat_viewproj)

    render_mesh(mesh, asset.shader_program_depth_only)
end
function render_voxels(mesh::Mesh, asset::LayerRenderer,
                       offset::v3f, scale::v3f, camera::Cam3D,
                       total_elapsed_seconds::Float32,
                       camera_mat_viewproj::fmat4)
    # Set render state.
    set_depth_writes(true)
    set_depth_test(ValueTests.LessThan)
    set_blending(make_blend_opaque(BlendStateRGBA))
    # Disable culling until I can make sure all triangles are oriented correctly.
    #TODO: Figure out voxel triangle orientation.
    set_culling(FaceCullModes.Off)

    # Set uniforms.
    set_uniform(asset.shader_program, "u_world_offset", offset)
    set_uniform(asset.shader_program, "u_world_scale", scale)
    set_uniform(asset.shader_program, "u_mat_viewproj", camera_mat_viewproj)
    set_uniform(asset.shader_program, "u_camPos", camera.pos)
    set_uniform(asset.shader_program, "u_camForward", camera.forward)
    set_uniform(asset.shader_program, "u_camUp", camera.up)
    set_uniform(asset.shader_program, "u_totalSeconds", total_elapsed_seconds)
    for (u_name, texture) in asset.textures
        set_uniform(asset.shader_program, u_name, texture)
    end

    # Render, and take care of texture views.
    for texture in values(asset.textures)
        view_activate(get_view(texture))
    end
    render_mesh(mesh, asset.shader_program)
    for texture in values(asset.textures)
        view_deactivate(get_view(texture))
    end
end