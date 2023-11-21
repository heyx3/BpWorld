bpw_asset_path(relative::AbstractString) = joinpath(ASSETS_PATH, relative)

#################
##   Shaders   ##
#################

"
Compiles a shader for this project, handling `#include`s (crudely; relative to 'assets' folder)
    and applying `SHADER_CUTOFF_TOKEN`.
"
function compile_shaders( vert::AbstractString, frag::AbstractString
                          ;
                          insert_above_code::AbstractString = "",
                          program_kw...
                        )
    return Program(
        process_shader_contents(vert, insert_above_code),
        process_shader_contents(frag, insert_above_code),
        ; program_kw...
    )
end
"An alternative to `compile_shaders()` that takes file paths instead of shader text"
compile_shader_files(vert::AbstractString, frag::AbstractString; kw...) = compile_shaders(
    String(open(read, joinpath(ASSETS_PATH, vert))),
    String(open(read, joinpath(ASSETS_PATH, frag)))
    ; kw...
)
compile_shader_files(name_without_ext::AbstractString; kw...) = compile_shader_files(
    "$name_without_ext.vert",
    "$name_without_ext.frag"
    ; kw...
)

################
##   Assets   ##
################

mutable struct Assets
    # Textures:
    tex_quit_confirmation::Texture
    # Shaders:
    # Buffers:
end
@close_gl_resources(a::Assets)

"Loads all texture assets, in the order they're declared by the `Assets` struct."
function load_all_textures()::Tuple
    return tuple(
        load_tex(
            bpw_asset_path("QuitConfirmation.png"), vRGBAu8,
            SimpleFormat(FormatTypes.normalized_uint,
                         SimpleFormatComponents.RGBA,
                         SimpleFormatBitDepths.B8)
        )
    )
end

"Loads all shader assets, in the order they're declared by the `Assets` struct."
function load_all_shaders()::Tuple
    return tuple(
    )
end

function load_all_buffers()::Tuple
    return tuple(
    )
end


function Assets()
    textures::Tuple = load_all_textures()
    shaders::Tuple = load_all_shaders()
    buffers::Tuple = load_all_buffers()

    check_gl_logs("After asset initialization")
    return Assets(textures..., shaders..., buffers...)
end


###################
##   Interface   ##
###################


function reload_shaders(assets::Assets)
    shaders = load_all_shaders()
    (assets.prog_lighting, ) = shaders
end