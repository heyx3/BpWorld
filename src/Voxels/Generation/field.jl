"
Generates a continuous field (usually in the range 0 - 1),
    for the purpose of being turned into voxels.
See `VoxelField` below.
"
abstract type AbstractField end

"Pre-computes and returns some data, in preparation for evaluating the field on a specific grid"
prepare_field(field, grid_size_v3u) = nothing

"
Gets the field's value at a position (usually between 0 and 1).

The last argument is the output of `prepare_field()`; if you didn't implement it then ignore it.
"
generate_field(field, pos_v3f, prepared) = error("generate_field() not defined for ", typeof(field))
generate_field(field, pos_v3f          ) = error("generate_field() not defined for ", typeof(field))
generate_field(field, pos_v3f, ::Nothing) = generate_field(field, pos_v3f)

#TODO: fields should also compute derivatives/gradient, defaulting to finite-differences



"
Turns a smooth field into a voxel grid, by thresholding the field value.
Normally, values *below* the field represent empty space, but if the threshold is negative,
    then values *above* `abs(threshold)` represent empty space instead.
"
Base.@kwdef struct VoxelField{TField<:AbstractField} <: AbstractVoxelGenerator
    layer::UInt8
    field::TField

    threshold::Float32 = @f32(0.5)
    pos_scale::v3f = one(v3f)
end
@inline prepare_generation(f::VoxelField, grid_size::v3u) = prepare_field(f.field, grid_size)
@inline function generate(f::VoxelField, ::v3u, pos::v3f, prepared_data)
    val::Float32 = generate_field(f.field, pos * f.pos_scale, prepared_data)
    is_past_threshold::Bool = if f.threshold < 0
        val < -f.threshold
    else
        val > f.threshold
    end
    return is_past_threshold ? f.layer : EMPTY_VOXEL
end


################
##   Perlin   ##
################

"3D perlin noise"
Base.@kwdef struct Perlin{TInModifier, TOutModifier} <: AbstractField
    scale::v3f = one(v3f)
    seed::UInt8 = 0xaa
    input_modifier::TInModifier = (pos::v3f) -> pos
    output_modifier::TOutModifier = (pos::v3f, field::Float32) -> field
end
"Standard Perlin noise"
Perlin(scale::v3f = one(v3f); kw...) = Perlin(scale=scale, kw...)
"Perlin noise with sharp ridges"
RidgedPerlin(scale::v3f = one(v3f); kw...) = Perlin(;
    scale=scale,
    kw...,
    # If the user provided a modifier, apply it on top of this one.
    output_modifier = let ridged_modifier = (pos::v3f, input::Float32) ->
                                                (@f32(2) * abs(input - @f32(0.5)))
        if hasproperty(kw, :output_modifier)
            outer_modifier = kw.output_modifier
            (pos::v3f, input::Float32) -> outer_modifier(pos, ridged_modifier(pos, input))
        else
            ridged_modifier
        end
    end
)
"Perlin noise that does a better job of looking like organic terrain"
BillowedPerlin(scale::v3f = one(v3f); kw...) = Perlin(;
    scale=scale,
    kw...,
    # If the user provided a modifier, apply it on top of this one.
    output_modifier = let billowed_modifier = (pos::v3f, input::Float32) -> (input*input)
        if hasproperty(kw, :output_modifier)
            outer_modifier = kw.output_modifier
            (pos::v3f, input::Float32) -> outer_modifier(pos, billowed_modifier(pos, input))
        else
            billowed_modifier
        end
    end
)

@inline function generate_field(p::Perlin, pos::v3f)
    pos = p.input_modifier(pos * p.scale)
    noise = perlin(pos, tuple(p.seed))
    return p.output_modifier(pos, noise)
end


######################
##   Octave Noise   ##
######################

"
Sums up a series of fields with varying weights and scales.
Each child field is called an 'octave'.
"
Base.@kwdef struct OctaveNoise{TChildTuple <: Tuple} <: AbstractField
    children::TChildTuple # Each child is @NamedTuple{scale::Float32, weight::Float32,
                          #                           n::AbstractFieldVoxelGenerator}
    normalize_scale::Float32 = @f32(1) / sum(c->c.weight, children, init=@f32(0))

    scale::v3f = one(v3f)
    seed::UInt8 = 0xbb
end
"Repeats one kind of noise `n` times, with increasing scale and decreasing weight"
function OctaveNoise( prototype::T,
                      n::Int,
                      persistence::Float32 = @f32(2)
                      ;
                      kw...
                    ) where {T<:AbstractField}
    return OctaveNoise{NTuple{n, @NamedTuple{scale::Float32, weight::Float32, n::T}}}(;
        children = ntuple(n) do i
            level::Float32 = persistence ^ (i - 1)
            return (scale = level,
                    weight = @f32(1) / level,
                    n=prototype)
        end,
        kw...
    )
end
"Uses an explicit group of fields and their scales/weights"
@inline function OctaveNoise(children::@NamedTuple{scale, weight, n}...; kw...)
    ChildTupleType = Tuple{(
        @NamedTuple{scale::Float32, weight::Float32, n::typeof(c.n)}
          for c in children
    )...}
    return OctaveNoise{ChildTupleType}(;
        children = map(children) do c
            (scale=convert(Float32, c.scale),
             weight=convert(Float32, c.weight),
             n=c.n)
        end,
        kw...
    )
end
"Takes a list of fields and assigns them increasing scale/decreasing weight"
@inline function OctaveNoise(children::AbstractField...
                             ; persistence::Float32 = @f32(2),
                               kw...)
    ChildTupleType = Tuple{(
        @NamedTuple{scale::Float32, weight::Float32, n::typeof(c)}
           for c in children
    )...}
    return OctaveNoise{ChildTupleType}(;
        children = ntuple(length(children)) do i
            level::Float32 = persistence ^ (i - 1)
            (scale=level, weight = @f32(1) / level, n = children[i])
        end,
        kw...
    )
end

@inline prepare_field(o::OctaveNoise, grid_size::v3u) = tuple((
    prepare_field(child.n, grid_size)
        for child in o.children
)...)
function generate_field(o::OctaveNoise, pos::v3f, prepared::Tuple)
    if sizeof(o.children) == 0
        return @f32(0)
    end

    #TODO: Make sure this loop gets unrolled.
    sum::Float32 = +((
        child.weight * generate_field(child.n, pos * child.scale, prepared[child_i])
          for (child_i, child) in enumerate(o.children)
    )...)

    return sum * o.normalize_scale
end


##############
##   Math   ##
##############

"A field with a constant value everywhere"
struct ConstField <: AbstractField
    value::Float32
end
@inline generate_field(f::ConstField, ::v3f) = f.value


"A field whose value is based on a math operation on some other fields"
struct MathField{TFunc, TArgs<:Tuple} <: AbstractField
    func::TFunc  # (Float32...) -> Float32
    args::TArgs
end
@inline MathField(func, args::AbstractField...) = MathField{typeof(func), typeof(args)}(func, args)
@inline prepare_field(f::MathField, grid_size::v3u) = tuple((
    prepare_field(arg, grid_size)
        for arg in f.args
)...)
@inline function generate_field(f::MathField, p::v3f, prep_data::Tuple)
    args = tuple((
        generate_field(arg, p, prep_data[i])
            for (i, arg) in enumerate(f.args)
    )...)
    return f.func(args...)
end


#TODO: Worley noise
#TODO: Refactor shapes to be fields rather than just voxels


################
##   Custom   ##
################

"Allows you to specify a custom field function"
Base.@kwdef struct CustomField{TFunc} <: AbstractField
    func::TFunc  # (pos::v3f) -> Float32
    scale::v3f = one(v3f)
end

@inline generate_field(p::CustomField, pos::v3f) = p.func(pos * p.scale)