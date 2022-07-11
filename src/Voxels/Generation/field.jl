"
Generates voxels by generating a continuous field (0-1 values) and thresholding it.
Field generators are expected to have the following fields:
  * `layer::UInt8` : which voxel layer the field outputs
  * `threshold::Float32` : Field values above this threshold represent solid voxels.
       If negative, then it represents the opposite
       (e.x. `-0.7` means that field values *below* 0.7 are solid voxels).

Without those fields, a new field type will need to reimplement `generate()` for itself.
"
abstract type AbstactFieldVoxelGenerator <: AbstractVoxelGenerator end

"The underlying field function used to get a voxel's value."
generate_field(n::AbstactFieldVoxelGenerator, ::v3u, ::v3f, ::Any) = error(
    "generate_field() not defined for ", typeof(n)
)
generate_field(n::AbstactFieldVoxelGenerator, i::v3u, p::v3f, ::Nothing) = generate_field(n, i, p)
generate_field(n::AbstactFieldVoxelGenerator, i::v3u, p::v3f) = error(
    "generate_field() not defined for ", typeof(n)
)

#TODO: Analytical derivatives, defaulting to finite-differences


function generate(n::AbstactFieldVoxelGenerator,
                  voxel_idx::v3u, pos::v3f, prepared_data)::UInt8
    field_val = generate_field(n, voxel_idx, pos, prepared_data)
    return if n.threshold < 0
        (field_val < -n.threshold) ? n.layer : EMPTY_VOXEL
    else
        (field_val > n.threshold) ? n.layer : EMPTY_VOXEL
    end
end


################
##   Perlin   ##
################

"3D perlin noise"
Base.@kwdef struct Perlin{TModifier} <: AbstactFieldVoxelGenerator
    layer::UInt8
    threshold::Float32 = @f32(0.5)

    scale::v3f

    modifier::TModifier = (unscaled_pos::v3f, field::Float32) -> field
    seed::UInt8 = 0xaa
end
"Perlin noise with sharp ridges"
RidgedPerlin(; kw...) = Perlin(;
    kw...,
    # If the user provided a modifier, apply it on top of this one.
    modifier = let ridged_modifier = (pos::v3f, input::Float32) ->
                                         (@f32(2) * abs(input - @f32(0.5)))
        if hasproperty(kw, :modifier)
            outer_modifier = kw.modifier
            (pos::v3f, input::Float32) -> outer_modifier(pos, ridged_modifier(pos, input))
        else
            ridged_modifier
        end
    end
)
"Perlin noise that does a better job of looking like organic terrain"
BillowedPerlin(; kw...) = Perlin(;
    kw...,
    # If the user provided a modifier, apply it on top of this one.
    modifier = let billowed_modifier = (pos::v3f, input::Float32) -> (input*input)
        if hasproperty(kw, :modifier)
            outer_modifier = kw.modifier
            (pos::v3f, input::Float32) -> outer_modifier(pos, billowed_modifier(pos, input))
        else
            billowed_modifier
        end
    end
)

@inline generate_field(p::Perlin, ::v3u, pos::v3f) = p.modifier(pos, perlin(pos * p.scale, tuple(p.seed)))


#TODO: Worley noise
#TODO: Octave noise
#TODO: "Math op" field
#TODO: Refactor shapes to be fields rather than just for voxels


################
##   Custom   ##
################

"Allows you to specify a custom field function"
Base.@kwdef struct CustomField{TFunc} <: AbstactFieldVoxelGenerator
    layer::UInt8
    threshold::Float32 = 0.5

    scale::v3f
    func::TFunc  # (pos::v3f) -> Float32
end

@inline generate_field(p::CustomField, ::v3u, pos::v3f) = p.func(pos * p.scale)