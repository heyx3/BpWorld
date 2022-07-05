const ASSETS_FOLDER = joinpath(@__DIR__, "..", "assets")
macro bpw_asset_str(str::AbstractString)
    return joinpath(ASSETS_FOLDER, str)
end

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
                after_directive = @view str[last(try_find):end]
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
                @info "Including: '$file_name'" full_statement=(@view str[include_statement_range])
                # Read the file that was included.
                file_path = abspath(joinpath(ASSETS_FOLDER, file_name))
                local file_contents::AbstractString
                if file_path in included_already
                    file_contents = ""
                else
                    push!(included_already, file_contents)
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



mutable struct Assets
    tex_tile::Texture
    tex_quit_confirmation::Texture
    prog_voxel::Program
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


function Assets()
    # Tile texture:
    tex_tile_pixels_raw::AbstractMatrix = load(bpw_asset"Tile.png")
    tex_tile_pixels = Matrix{UInt8}(undef, (size(tex_tile_pixels_raw, 2),
                                            size(tex_tile_pixels_raw, 1)))
    for p::v2i in 1:v2i(size(tex_tile_pixels))
        input = tex_tile_pixels_raw[size(tex_tile_pixels, 2) - p.y + 1, p.x]
        tex_tile_pixels[p] = reinterpret(input.r)
    end
    tex_tile = Texture(
        SimpleFormat(FormatTypes.normalized_uint,
                     SimpleFormatComponents.R,
                     SimpleFormatBitDepths.B8),
        tex_tile_pixels
    )

    # Quit confirmation texture:
    tex_quitconf_pixels_raw::AbstractMatrix = load(bpw_asset"QuitConfirmation.png")
    tex_quitconf_pixels = Matrix{vRGBAu8}(undef, (size(tex_quitconf_pixels_raw, 2),
                                                  size(tex_quitconf_pixels_raw, 1)))
    for p::v2i in 1:v2i(size(tex_quitconf_pixels))
        pixel = tex_quitconf_pixels_raw[size(tex_quitconf_pixels, 2) - p.y + 1, p.x]
        v = Vec(reinterpret(red(pixel)),
                reinterpret(green(pixel)),
                reinterpret(blue(pixel)),
                reinterpret(alpha(pixel)))
        vF = v / typemax(typeof(v.x))
        v_out = map(round, vF) * typemax(UInt8)
        tex_quitconf_pixels[p] = convert(vRGBAu8, v_out)
    end
    tex_quitconf = Texture(
        SimpleFormat(FormatTypes.normalized_uint,
                     SimpleFormatComponents.RGBA,
                     SimpleFormatBitDepths.B8),
        tex_quitconf_pixels
    )

    # Voxel shader program:
    prog_voxel = compile_shader_files("voxel")

    return Assets(tex_tile, tex_quitconf, prog_voxel)
end


"
Configures the parameters of the voxel shader,
    and sets render state accordingly.

Does not activate texture views!
"
function prepare_program_voxel( assets::Assets,
                                world_mat::fmat4, viewproj_mat::fmat4,
                                albedo_rgb::Texture,
                                cam_pos::v3f, cam_dir::v3f,
                                specular::Float32 = @f32(0.5),
                                specular_power::Float32 = @f32(86.0)
                              )
    set_uniform(assets.prog_voxel, "u_mat_world", world_mat)
    set_uniform(assets.prog_voxel, "u_mat_viewproj", viewproj_mat)
    set_uniform(assets.prog_voxel, "u_specular", specular)
    set_uniform(assets.prog_voxel, "u_specularDropoff", specular_power)
    set_uniform(assets.prog_voxel, "u_tex2d_albedo", albedo_rgb)
    set_uniform(assets.prog_voxel, "u_camPos", cam_pos)
    set_uniform(assets.prog_voxel, "u_camDir", cam_dir)

    # Disable culling until I can make sure all triangles are oriented correctly.
    #TODO: Figure out voxel triangle orientation.
    set_culling(FaceCullModes.Off)

    return
end