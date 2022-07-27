
"Converts an incoming pixel of a Julia image into GPU-friendly pixel data."
pixel_converter(input, Output::Type)::Output = error("Can't convert a ", typeof(input), " into a ", Output)

# Identity conversion:
pixel_converter(u::U, ::Type{U}) where {U} = u

# Convert unsigned into signed by effectively subtracting half the range.
pixel_converter(u::U, I::Type{<:Signed}) where {U<:Unsigned} = (I == signed(U)) ?
                                                                   typemax(signed(U)) + reinterpret(signed(U), u) + one(signed(U)) :
                                                                   error(I, " isn't the signed version of ", U)
# Fixed-point already is an unsigned format, just need to reinterpret it.
pixel_converter(u::N0f8, I::Type{<:Union{Int8, UInt8}}) = pixel_converter(reinterpret(u), I)

# Take whatever subset of color channels the user desires.
pixel_converter(p_in::Colorant, T::Type{<:Union{Int8, UInt8}}) = pixel_converter(red(p_in), T)
pixel_converter(p_in::Colorant, T::Type{<:Vec2{I}}) where {I<:Union{Int8, UInt8}} = T(pixel_converter(red(p_in), I),
                                                                                      pixel_converter(green(p_in), I))
pixel_converter(p_in::Colorant, T::Type{<:Vec3{I}}) where {I<:Union{Int8, UInt8}} = T(pixel_converter(red(p_in), I),
                                                                                      pixel_converter(green(p_in), I),
                                                                                      pixel_converter(blue(p_in), I))
pixel_converter(p_in::Colorant, T::Type{<:Vec4{I}}) where {I<:Union{Int8, UInt8}} = T(pixel_converter(red(p_in), I),
                                                                                      pixel_converter(green(p_in), I),
                                                                                      pixel_converter(blue(p_in), I),
                                                                                      pixel_converter(alpha(p_in), I))

"Read a texture, convert its pixels into the desired format, and create it."
function load_tex( full_path::AbstractString,
                   ::Type{TOutPixel},
                   tex_format::TexFormat,
                   converter::TConverter = pixel_converter
                   ;
                   tex_args...
                 )::Texture where {TOutPixel, TConverter}
    pixels_raw::Matrix = load(full_path)
    raw_tex_size = v2i(size(pixels_raw)...)

    tex_size = raw_tex_size.yx
    pixels = Matrix{TOutPixel}(undef, tex_size.data)
    for p_out::v2i in 1:v2i(tex_size)
        p_in = v2i(tex_size.y - p_out.y + Int32(1), p_out.x)
        pixels[p_out] = converter(pixels_raw[p_in], TOutPixel)
    end

    return Texture(tex_format, pixels; tex_args...)
end