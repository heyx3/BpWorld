##################
##   Textures   ##
##################

"The data definition for a specific texture file"
struct LayerDataTexture
    # This texture's name in the shader.
    # E.x. if you use "tex_albedo", then the shader
    #    will automatically define "uniform sampler2D tex_albedo;".
    code_name::String

    # The default sampler is good for typical 3D meshes:
    #    repeat, linear filtering, mipmaps, and anisotropy based on graphics settings.
    sampler::Optional{TexSampler{2}}

    channels::E_SimpleFormatComponents
    use_mips::Bool

    LayerDataTexture(code_name::String
                 ;
                 sampler::Optional{TexSampler{2}} = nothing,
                 channels::E_SimpleFormatComponents = SimpleFormatComponents.RGBA,
                 use_mips::Bool = true
                ) = new(code_name, sampler, channels, use_mips)
    # This constructor handles 'nothing' values for each field, for StructTypes deserialization.
    LayerDataTexture(code_name, sampler, channels, use_mips) = new(
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
StructTypes.StructType(::Type{LayerDataTexture}) = StructTypes.UnorderedStruct()


#########################
##   Lighting Models   ##
#########################

"
The choice of lighting model, plus any associated settings.

Serialization is done by writing/reading all properties of the concrete object,
    plus a special field representing the model's unique type identifier.
If a concrete type overloads the serialization behavior, it must remember to add the 'model' field too!
"
abstract type AbstractLayerDataLightingModel end

# Use a name to distinguish each type of lighting model.
const LIGHTING_MODEL_TYPE_KEY = :model
lighting_model_serialized_name(T::Type{AbstractLayerDataLightingModel})::Symbol = error(T, " doesn't implement lighting_model_serialized_name()")
lighting_model_type(::Val{SerializedName}) where {SerializedName} = error("Lighting model '", SerializedName, "' isn't supported")

StructTypes.StructType(::Type{AbstractLayerDataLightingModel}) = StructTypes.Custom()
StructTypes.lowertype(::Type{<:AbstractLayerDataLightingModel}) = Dict{Symbol, Any}()
StructTypes.lower(lm::AbstractLayerDataLightingModel) = Dict{Symbol, Any}(
    LIGHTING_MODEL_TYPE_KEY => lighting_model_serialized_name(typeof(lm)),
    (f => getproperty(lm, f) for f in propertynames(lm))...
)
function StructTypes.construct(::Type{AbstractLayerDataLightingModel}, data::Dict{Symbol, Any})
    if !haskey(data, LIGHTING_MODEL_TYPE_KEY)
        error("Lighting model data is missing its '", LIGHTING_MODEL_TYPE_KEY, "' field")
    end
    TConcrete = lighting_model_type(Val(data[LIGHTING_MODEL_TYPE_KEY]))

    # Delegate the actual creation to child types in case they want to customize it.
    data = copy(data)
    delete!(data, LIGHTING_MODEL_TYPE_KEY)
    return StructTypes.construct(TConcrete)
end
function StructTypes.construct(T::Type{<:AbstractLayerDataLightingModel}, data_dict)
    # By default, feed each property into the constructor in the order they're declared.
    input_names = propertynames(T)
    input_values = map(name -> get(data_dict, name, nothing), input_names)

    # Warn the user in case of a typo or other misunderstanding.
    for field in keys(data_dict)
        if !(field in input_names)
            @warn "Unexpected field in $(lighting_model_serialized_name(T)): '$field'"
        end
    end

    return T(input_values)
end


###############
##   Layer   ##
###############

"The data definition for a specific voxel layer"
struct LayerDefinition
    # The fragment shader file.
    # The vertex shader will always be "voxels/meshed.vert"
    frag_shader_path::AbstractString

    # The lighting model this layer will use.
    lighting_model::AbstractLayerDataLightingModel

    # The textures used by this voxel asset.
    # The keys are the file names, relative to the root folder for all voxel layers.
    #TODO: relative to the root folder if it starts with a slash, relative to the layer JSON file otherwise
    textures::Dict{AbstractString, LayerDataTexture}

    # Any #defines you want to add in the fragment shader.
    # The keys are the token names, and the values are the token values.
    # E.x. the value "ABC" => "1" translates into "#define ABC 1".
    #TODO: If given an array of strings, turn them into multiple lines connected by backslash
    preprocessor_defines::Dict{AbstractString, AbstractString}

    # This constructor handles 'nothing' values for each field, for StructTypes deserialization.
    LayerDefinition(frag_shader_path, lighting_model, textures, preprocessor_defines) = new(
        isnothing(frag_shader_path) ?
            error("Field 'frag_shader_path' must be set for a voxel layer!") :
            frag_shader_path,
        isnothing(lighting_model) ?
            error("Field 'lighting_model' must be set for a voxel layer!") :
            lighting_model,
        isnothing(textures) ?
            Dict{AbstractString, LayerDataTexture}() :
            textures,
        isnothing(preprocessor_defines) ?
            Dict{AbstractString, AbstractString}() :
            preprocessor_defines
    )
end
StructTypes.StructType(::Type{LayerDefinition}) = StructTypes.UnorderedStruct()