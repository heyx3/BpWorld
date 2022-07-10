println("#TODO: rename 'Asset' to 'Layer'.")

"The data definition for a specific voxel material."
struct AssetData
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


    # Any #defines you want to add in the fragment shader.
    # The keys are the token names, and the values are the token values.
    # E.x. the value "ABC" => "1" translates into "#define ABC 1".
    preprocessor_defines::Dict{AbstractString, AbstractString}

    # This constructor handles 'nothing' values for each field, for StructTypes deserialization.
    AssetData(frag_shader_path, textures, samplers, preprocessor_defines) = new(
        isnothing(frag_shader_path) ?
            error("Field 'frag_shader_path' must be set for a voxel asset!") : #TODO: Default to an 'error' shader.
            frag_shader_path,
        isnothing(textures) ?
            Dict{AbstractString, AbstractString}() :
            textures,
        isnothing(samplers) ?
            Dict{AbstractString, Sampler{2}}() :
            samplers,
        isnothing(preprocessor_defines) ?
            Dict{AbstractString, AbstractString}() :
            preprocessor_defines
    )
end

# Serialization:
StructTypes.StructType(::Type{AssetData}) = StructTypes.UnorderedStruct()


"A renderable voxel material."
mutable struct AssetRenderer
    shader_program::Program

    # Each texture is mapped to its uniform name.
    textures::Dict{AbstractString, Texture}
end
function AssetRenderer(data::AssetData)
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

    shader_inputs = tuple(("voxels.vert", "vertex", defines),
                          (data.frag_shader_path, "fragment", fragment_header))
    shader_contents = map(shader_inputs) do (path, type, header)
        # Check that the file exists.
        full_path = joinpath(VOXELS_ASSETS_PATH, path)
        if !isfile(full_path)
            error(type, " shader file doesn't exist: '", full_path, "'")
        end

        # Load and pre-process the file.
        contents = open(io -> read(io, String), full_path, "r")
        try
            contents = process_shader_contents(contents, header)
        catch e
            error("Failed to preprocess ", type, " shader: ", e)
        end
    end
    program = Program(shader_contents..., flexible_mode=true)

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

    return AssetRenderer(program, textures)
end

function Base.close(a::AssetRenderer)
    close(a.shader_program)
    for tex in values(a.textures)
        close(tex)
    end
    empty!(a.textures)
end


function render_voxels(mesh::Mesh, asset::AssetRenderer,
                       offset::v3f, scale::v3f, camera::Cam3D,
                       total_elapsed_seconds::Float32)
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
    set_uniform(asset.shader_program, "u_mat_viewproj",
                m_combine(cam_view_mat(camera), cam_projection_mat(camera)))
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