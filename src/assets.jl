bpw_asset_path(relative::AbstractString) = joinpath(ASSETS_PATH, relative)


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