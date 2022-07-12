module Utils

using Setfield, Base.Threads,
      Suppressor, StructTypes, JSON3
using GLFW, ModernGL, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input
#


"Asserts for this specific project: `@bpworld_assert`, `@bpworld_debug`."
@make_toggleable_asserts bpworld_
@assert bpworld_asserts_enabled() == false

"
Removes the type declaration.
This allows you to make a 'default' implementation that explicitly lists types,
    but still doesn't risk ambiguity with more specific overloads.
"
macro omit_type(var_decl)
    @assert(Meta.isexpr(var_decl, :(::)) && isa(var_decl.args[1], Symbol),
            "Expected a typed variable declaration, got: $var_decl")
    return esc(var_decl.args[1])
end


"Checks and prints any messages/errors from OpenGL. Does nothing in release mode."
function check_gl_logs(context::String)
    @bpworld_debug for log in pull_gl_logs()
        if log.severity in (DebugEventSeverities.high, DebugEventSeverities.medium)
            @error "While $context. $(sprint(show, log))"
        elseif log.severity == DebugEventSeverities.low
            @warn "While $context. $(sprint(show, log))"
        elseif log.severity == DebugEventSeverities.none
            @info "While $context. $(sprint(show, log))"
        else
            error("Unhandled case: ", log.severity)
        end
    end
    return nothing
end


"The path where all assets should be placed"
const ASSETS_PATH = joinpath(@__DIR__, "..", "..", "assets")

"
Any shader code before this token is removed.
This allows you to add things for the IDE/linter only.
"
const SHADER_CUTOFF_TOKEN = "#J#J#"

"Processes a shader file to remove the `SHADER_CUTOFF_TOKEN` and execute `#include` statements."
function process_shader_contents(str::AbstractString, insert_at_top::AbstractString = "")
    # First, cut off everything above the special cutoff token.
    while true
        try_find::Optional{UnitRange{Int}} = findfirst(SHADER_CUTOFF_TOKEN, str)
        if isnothing(try_find)
            break
        else
            #TODO: Insert a '#line' statement (should be easy here, just count newlines).
            str = str[last(try_find)+1 : end]
        end
    end

    # Next, inject any desired code at the top of the file.
    str = "$insert_at_top\n$str"

    # Finally, recursively evaluate include statements.
    included_already = Set{AbstractString}() # Don't double-include
    while true
        try_find::Optional{UnitRange{Int}} = findfirst("#include", str)
        if isnothing(try_find)
            break
        else
            stop_idx = findnext('\n', str, last(try_find))
            if isnothing(stop_idx)
                stop_idx = length(str)
            end
            after_directive = @view str[last(try_find):stop_idx]
            # Find the opening of the file name.
            name_start = findfirst('"', after_directive)
            name_end_char = '"'
            if isnothing(name_start)
                name_start = findfirst('<', after_directive)
                name_end_char = '>'
                if isnothing(name_start)
                    error("Couldn't find the name for an #include statement")
                end
            end
            # Find the closing of the file-name.
            after_name_opening = @view after_directive[name_start + 1 : end]
            name_end = findfirst(name_end_char, after_name_opening)
            if isnothing(name_end)
                error("Couldn't find the end of the file-name for an #include statement")
            end
            # Calculate the exact position of the include statement and the file-name;
            #     'name_start' and 'name_end' are both relative indices.
            name_start_idx = last(try_find) + name_start
            name_end_idx = name_start_idx + name_end - 2
            file_name = @view str[name_start_idx:name_end_idx]
            include_statement_range = first(try_find):(name_end_idx+1)
            # Read the file that was included.
            file_path = abspath(joinpath(ASSETS_PATH, file_name))
            local file_contents::AbstractString
            if file_path in included_already
                file_contents = ""
            else
                push!(included_already, file_path)
                file_contents = String(open(read, file_path, "r"))
                # Inject a '#line' directive before and afterwards.
                incoming_line = "#line 1"
                # The line directive afterwards is hard to count, so for now
                #    set it to an obviously-made-up value to prevent red-herrings.
                #TODO: If we process includes from last to first, then line counts would be correct. However, we'd have to keep moving the included code backwards to the first instance of each file being included. So you'd have to insert stand-in tokens that get replaced at the end of include processing.
                outgoing_line = "#line 99999"
                file_contents = "$incoming_line\n$file_contents\n$outgoing_line"
            end
            # Update the file for the include() statement.
            str_chars = collect(str)
            splice!(str_chars, include_statement_range, file_contents)
            str = String(str_chars)
        end
    end

    return str
end


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


export @bpworld_assert, @bpworld_debug,
       @omit_type,
       check_gl_logs,
       ASSETS_PATH, process_shader_contents,
       pixel_converter, load_tex

end