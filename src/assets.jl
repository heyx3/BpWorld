const ASSETS_FOLDER = joinpath(@__DIR__, "..", "assets")
macro bpw_asset_str(str::AbstractString)
    return joinpath(ASSETS_FOLDER, str)
end

#################
##   Shaders   ##
#################

"
Any shader code before this token is removed.
This allows you to add things for the IDE/linter that get ignored by this game.
"
const SHADER_CUTOFF_TOKEN = "#J#J#"

"
Compiles a shader for this project, handling `#include`s (crudely; relative to 'assets' folder)
    and applying `SHADER_CUTOFF_TOKEN`.
"
compile_shaders(vert::AbstractString, frag::AbstractString) = begin
    process_contents(str::AbstractString, description::AbstractString) = begin
        # First, recursively evaluate include statements.
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
                        error("Couldn't find the name for an #include statement, in ", description)
                    end
                end
                # Find the closing of the file-name.
                after_name_opening = @view after_directive[name_start + 1 : end]
                name_end = findfirst(name_end_char, after_name_opening)
                if isnothing(name_end)
                    error("Couldn't find the end of the file-name for an #include statement, in ", description)
                end
                # Calculate the exact position of the include statement and the file-name;
                #     'name_start' and 'name_end' are both relative indices.
                name_start_idx = last(try_find) + name_start
                name_end_idx = name_start_idx + name_end - 2
                file_name = @view str[name_start_idx:name_end_idx]
                include_statement_range = first(try_find):(name_end_idx+1)
                @info("Including: '$file_name'",
                    full_statement=(@view str[include_statement_range])
                )
                # Read the file that was included.
                file_path = abspath(joinpath(ASSETS_FOLDER, file_name))
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

        # Next, cut off everything above the special cutoff token.
        while true
            try_find::Optional{UnitRange{Int}} = findfirst(SHADER_CUTOFF_TOKEN, str)
            if isnothing(try_find)
                break
            else
                #TODO: Insert a '#line' statement (should be easy here, just count newlines).
                str = str[last(try_find)+1 : end]
            end
        end

        return str
    end

    return Program(process_contents.((vert, frag), ("vertex shader", "fragment shader"))...)
end
"An alternative to `compile_shaders()` that takes file paths instead of shader text"
compile_shader_files(vert::AbstractString, frag::AbstractString) = compile_shaders(
    String(open(read, joinpath(ASSETS_FOLDER, vert))),
    String(open(read, joinpath(ASSETS_FOLDER, frag)))
)
compile_shader_files(name_without_ext::AbstractString) = compile_shader_files(
    "$name_without_ext.vert",
    "$name_without_ext.frag"
)


##################
##   Textures   ##
##################

# Define a helper to convert loaded image data into a specific GPU format,
#    usually normalized-int or normalized-uint.

default_pixel_converter(u::U, ::Type{U}) where {U} = u
default_pixel_converter(u::U, I::Type{<:Signed}) where {U<:Unsigned} = (I == signed(U)) ?
                                                                           typemax(signed(U)) + reinterpret(signed(U), u) + one(signed(U)) :
                                                                           error(I, " isn't the signed version of ", U)
default_pixel_converter(u::N0f8, I::Type{<:Union{Int8, UInt8}}) = default_pixel_converter(reinterpret(u), I)

default_pixel_converter(p_in::Colorant, T::Type{<:Union{Int8, UInt8}}) = default_pixel_converter(red(p_in), T)
default_pixel_converter(p_in::Colorant, T::Type{<:Vec2{I}}) where {I<:Union{Int8, UInt8}} = T(default_pixel_converter(red(p_in), I),
                                                                                              default_pixel_converter(green(p_in), I))
default_pixel_converter(p_in::Colorant, T::Type{<:Vec3{I}}) where {I<:Union{Int8, UInt8}} = T(default_pixel_converter(red(p_in), I),
                                                                                              default_pixel_converter(green(p_in), I),
                                                                                              default_pixel_converter(blue(p_in), I))
default_pixel_converter(p_in::Colorant, T::Type{<:Vec4{I}}) where {I<:Union{Int8, UInt8}} = T(default_pixel_converter(red(p_in), I),
                                                                                              default_pixel_converter(green(p_in), I),
                                                                                              default_pixel_converter(blue(p_in), I),
                                                                                              default_pixel_converter(alpha(p_in), I))


function load_tex( full_path::AbstractString,
                   ::Type{TOutPixel},
                   tex_format::TexFormat,
                   converter::TConverter = default_pixel_converter
                   ;
                   tex_args...
                 )::Texture where {TOutPixel, TConverter}
    pixels_raw::Matrix = load(full_path)
    raw_tex_size = v2i(size(pixels_raw)...)

    tex_size = raw_tex_size.yx
    pixels = Matrix{TOutPixel}(undef, tex_size.data)
    for p_out::v2i in 1:v2i(tex_size)
        p_in = v2i(tex_size.y - p_out.y + 1, p_out.x)
        pixels[p_out] = converter(pixels_raw[p_in], TOutPixel)
    end

    return Texture(tex_format, pixels; tex_args...)
end


################
##   Assets   ##
################

mutable struct Assets
    tex_tile::Texture

    tex_rocks_albedo::Texture
    tex_rocks_normals::Texture
    tex_rocks_surface::Texture

    tex_quit_confirmation::Texture

    prog_voxel::Program
    prog_lighting::Program
end
function Base.close(a::Assets)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple()
    whitelist = setdiff(fieldnames(typeof(a)), blacklist)
    for field in whitelist
        close(getfield(a, field))
    end
end

"Loads all texture assets, in the order they're declared by the `Assets` struct."
function load_all_textures()::Tuple
    scene_sampler = Sampler{2}(
        wrapping = WrapModes.repeat
    )
    return tuple(
        load_tex(
            bpw_asset"Tile.png", UInt8,
            SimpleFormat(FormatTypes.normalized_uint,
                        SimpleFormatComponents.R,
                        SimpleFormatBitDepths.B8),
            sampler = scene_sampler
        ),

        load_tex(
            bpw_asset"scene/Rocks-Albedo.png", vRGBu8,
            SimpleFormat(FormatTypes.normalized_uint,
                         SimpleFormatComponents.RGB,
                         SimpleFormatBitDepths.B8),
            sampler = scene_sampler
        ),
        load_tex(
            #TODO: Try loading this at a lower quality/specialized format
            bpw_asset"scene/Rocks-Normal.png", vRGBi8,
            SimpleFormat(FormatTypes.normalized_int,
                         SimpleFormatComponents.RGB,
                         SimpleFormatBitDepths.B8),
            sampler = scene_sampler
        ),
        load_tex(
            #TODO: Try loading this at a lower quality/specialized format
            bpw_asset"scene/Rocks-Surface.png", Vec2{UInt8},
            SimpleFormat(FormatTypes.normalized_uint,
                         SimpleFormatComponents.RG,
                         SimpleFormatBitDepths.B8),
            sampler = scene_sampler
        ),

        load_tex(
            bpw_asset"QuitConfirmation.png", vRGBAu8,
            SimpleFormat(FormatTypes.normalized_uint,
                         SimpleFormatComponents.RGBA,
                         SimpleFormatBitDepths.B8)
        )
    )
end

"Loads all shader assets, in the order they're declared by the `Assets` struct."
function load_all_shaders()::Tuple
    return tuple(
        compile_shader_files("scene/voxel"),
        compile_shader_files("post_processing/quad.vert",
                             "post_processing/lighting.frag")
    )
end

function Assets()
    textures::Tuple = load_all_textures()
    shaders::Tuple = load_all_shaders()

    check_gl_logs("After asset initialization")
    return Assets(textures..., shaders...)
end


###################
##   Interface   ##
###################

"The type of sampling used for G-buffer textures in full-screen passes."
const G_BUFFER_SAMPLER = Sampler{2}(
    wrapping = WrapModes.clamp,
    pixel_filter = PixelFilters.rough,
    mip_filter = nothing
)

"
Configures the parameters of the voxel shader,
    and sets render state accordingly.

Does not activate texture views!
"
function prepare_program_voxel( assets::Assets,
                                world_pos::v3f, world_scale::v3f,
                                viewproj_mat::fmat4
                              )
    set_uniform(assets.prog_voxel, "u_offset", world_pos)
    set_uniform(assets.prog_voxel, "u_scale", world_scale)
    set_uniform(assets.prog_voxel, "u_mat_viewproj", viewproj_mat)
    set_uniform(assets.prog_voxel, "u_tex_albedo", assets.tex_rocks_albedo)
    set_uniform(assets.prog_voxel, "u_tex_surface", assets.tex_rocks_surface)

    # Disable culling until I can make sure all triangles are oriented correctly.
    #TODO: Figure out voxel triangle orientation.
    set_culling(FaceCullModes.Off)

    set_depth_writes(true)
    set_depth_test(ValueTests.LessThan)
    set_blending(make_blend_opaque(BlendStateRGBA))

    return nothing
end
function prepare_program_lighting( assets::Assets,
                                   tex_depth::Texture,
                                   tex_colors::Texture,
                                   tex_normals::Texture,
                                   tex_surface::Texture,
                                   light_dir::v3f,
                                   light_emission::vRGBf,
                                   cam::Cam3D
                                 )
    for uniforms in tuple(
        ("u_gBuffer.depth", get_view(tex_depth, G_BUFFER_SAMPLER)),
        ("u_gBuffer.colors", get_view(tex_colors, G_BUFFER_SAMPLER)),
        ("u_gBuffer.normals", get_view(tex_normals, G_BUFFER_SAMPLER)),
        ("u_gBuffer.surface", get_view(tex_surface, G_BUFFER_SAMPLER)),
        ("u_sunlight.dir", light_dir),
        ("u_sunlight.emission", light_emission),
        ("u_camera.pos", cam.pos),
        #("u_camera.nearClip", cam.clip_range.min),
        #("u_camera.farClip", max_inclusive(cam.clip_range)),
        ("u_camera.invViewProjMat", m_invert(m_combine(cam_view_mat(cam),
                                                       cam_projection_mat(cam)))),
    )
        set_uniform(assets.prog_lighting, uniforms...)
    end

    set_culling(FaceCullModes.Off)
    set_depth_writes(false)
    set_depth_test(ValueTests.Pass)
    set_blending(make_blend_opaque(BlendStateRGBA))
end

function reload_shaders(assets::Assets)
    # Is field enumeration order guaranteed?
    # It seems to work in the REPL.
    shaders = load_all_shaders()
    idx::Int = 1
    for field in fieldnames(Assets)
        if fieldtype(Assets, field) == Program
            setfield!(assets, field, shaders[idx])
            idx += 1
        end
    end
end