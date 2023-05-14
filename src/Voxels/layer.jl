#########################################
##   LayerData -- on-disk voxel layer  ##
#########################################

struct LayerTexture
    # This texture's name in the shader.
    # E.x. if you use "tex_albedo", then the shader
    #    will automatically define "uniform sampler2D tex_albedo;".
    code_name::String

    # The default sampler is good for typical 3D meshes:
    #    repeat, linear filtering, mipmaps, and anisotropy based on graphics settings.
    sampler::Optional{Sampler{2}}

    channels::E_SimpleFormatComponents
    use_mips::Bool

    LayerTexture(code_name::String
                 ;
                 sampler::Optional{Sampler{2}} = nothing,
                 channels::E_SimpleFormatComponents = SimpleFormatComponents.RGBA,
                 use_mips::Bool = true
                ) = new(code_name, sampler, channels, use_mips)
    # This constructor handles 'nothing' values for each field, for StructTypes deserialization.
    LayerTexture(code_name, sampler, channels, use_mips) = new(
        isnothing(code_name) ?
            error("Field 'code_name' must be provided for a texture") :
            code_name,
        sampler,
        isnothing(channels) ?
            SimpleFormatComponents.RGBA :
            channels,
        isnothing(use_mips) ?
            true :
            use_mips
    )
end
StructTypes.StructType(::Type{LayerTexture}) = StructTypes.UnorderedStruct()


"The data definition for a specific voxel material."
struct LayerData
    # The fragment shader file.
    # The vertex shader will always be "voxels/meshed.vert"
    frag_shader_path::AbstractString

    # The textures used by this voxel asset.
    # The keys are the file names, relative to the root folder for all voxel layers.
    #TODO: relative to the root folder if it starts with a slash, relative to the layer JSON file otherwise
    textures::Dict{AbstractString, LayerTexture}

    # Any #defines you want to add in the fragment shader.
    # The keys are the token names, and the values are the token values.
    # E.x. the value "ABC" => "1" translates into "#define ABC 1".
    #TODO: If given an array of strings, turn them into multiple lines connected by backslash
    preprocessor_defines::Dict{AbstractString, AbstractString}

    # This constructor handles 'nothing' values for each field, for StructTypes deserialization.
    LayerData(frag_shader_path, textures, preprocessor_defines) = new(
        isnothing(frag_shader_path) ?
            error("Field 'frag_shader_path' must be set for a voxel asset!") :
            frag_shader_path,
        isnothing(textures) ?
            Dict{AbstractString, LayerTexture}() :
            textures,
        isnothing(preprocessor_defines) ?
            Dict{AbstractString, AbstractString}() :
            preprocessor_defines
    )
end

# Serialization:
StructTypes.StructType(::Type{LayerData}) = StructTypes.UnorderedStruct()