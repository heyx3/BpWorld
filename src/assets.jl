macro bpw_asset_str(str::AbstractString)
    return joinpath(ASSETS_PATH, str)
end

#################
##   Shaders   ##
#################

"
Compiles a shader for this project, handling `#include`s (crudely; relative to 'assets' folder)
    and applying `SHADER_CUTOFF_TOKEN`.
"
compile_shaders(vert::AbstractString, frag::AbstractString; kw...) = begin
    return Program(process_shader_contents.((vert, frag))...; kw...)
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
    voxel_layers::Vector{Voxels.AssetRenderer}

    tex_quit_confirmation::Texture

    prog_lighting::Program
end
function Base.close(a::Assets)
    for L in a.voxel_layers
        close(L)
    end

    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple(:voxel_layers)
    whitelist = setdiff(fieldnames(typeof(a)), blacklist)
    for field in whitelist
        close(getfield(a, field))
    end
end

"Loads all texture assets, in the order they're declared by the `Assets` struct."
function load_all_textures()::Tuple
    return tuple(
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
        compile_shader_files("post_processing/quad.vert",
                             "post_processing/lighting.frag",
                             flexible_mode = true)
    )
end

function Assets()
    textures::Tuple = load_all_textures()
    shaders::Tuple = load_all_shaders()

    # Hard-code the voxel assets to load for now.
    voxel_assets = [
        Voxels.AssetRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "rocks", "rocks.json"),
                                             "r"),
                                        Voxels.AssetData))
    ]

    check_gl_logs("After asset initialization")
    return Assets(voxel_assets, textures..., shaders...)
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
        ("u_camera.nearClip", cam.clip_range.min),
        ("u_camera.farClip", max_inclusive(cam.clip_range)),
        ("u_camera.forward", cam.forward),
        ("u_camera.up", cam.up),
        ("u_camera.right", cam_rightward(cam)),
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