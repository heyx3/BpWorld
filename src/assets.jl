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
compile_shader_files(vert::AbstractString, frag::AbstractString; kw...) = begin
    @check_gl_logs("Before $vert and $frag")
    p = compile_shaders(
        String(open(read, joinpath(ASSETS_PATH, vert))),
        String(open(read, joinpath(ASSETS_PATH, frag)))
        ; kw...
    )
    @check_gl_logs("After $vert and $frag")
    return p
end
compile_shader_files(name_without_ext::AbstractString; kw...) = compile_shader_files(
    "$name_without_ext.vert",
    "$name_without_ext.frag"
    ; kw...
)

#################
##   Buffers   ##
#################

struct UBO_Fog
    density::Float32
    dropoff::Float32

    heightOffset::Float32
    heightScale::Float32

    color::vRGBf
    padding::UInt32

    UBO_Fog(density, dropoff, height_offset, height_scale, color) = new(
        density, dropoff,
        height_offset, height_scale,
        color, 0
    )
    UBO_Fog(gui_fog) = new(
        gui_fog.density, gui_fog.dropoff,
        gui_fog.height_offset, gui_fog.height_scale,
        gui_fog.color, 0
    )
end
@bp_check(sizeof(UBO_Fog) == sum(sizeof.(fieldtypes(UBO_Fog))),
          "Expected UBO_Fog to be $(sum(sizeof.(fieldtypes(UBO_Fog)))) bytes ",
            "but it was $(sizeof(UBO_Fog))")
const UBO_IDX_FOG = 1

struct UBO_Light
    dir::v4f
    color::vRGBAf

    shadowmap::Bplus.GL.Ptr_View
    shadow_bias::Float32
    padding_3::UInt32

    world_to_texel_mat::fmat4

    UBO_Light(dir, color, shadowmap, shadow_bias, world_to_texel_mat) = new(
        vappend(dir, 0),
        vappend(color, 1),

        if shadowmap isa Texture
            get_view(shadowmap).handle
        elseif shadowmap isa View
            shadowmap.handle
        else
            convert(Bplus.GL.Ptr_View, shadowmap)
        end,
        shadow_bias,
        0,

        world_to_texel_mat
    )
end
@bp_check(sizeof(UBO_Light) == sum(sizeof.(fieldtypes(UBO_Light))),
          "Expected UBO_Light to be $(sum(sizeof.(fieldtypes(UBO_Light)))) bytes ",
            "but it was $(sizeof(UBO_Light))")
const UBO_IDX_LIGHT = 2

struct UBO_Camera
    pos::v4f
    forward::v4f
    upward::v4f
    rightward::v4f

    near_clip::Float32
    far_clip::Float32
    padding_1::Float32
    padding_2::Float32

    mat_view::fmat4
    mat_projection::fmat4
    mat_view_proj::fmat4
    mat_inv_view_proj::fmat4


    UBO_Camera(pos, forward, upward, rightward,
               near_clip, far_clip,
               mat_view, mat_projection,
               mat_view_proj = m_combine(mat_view, mat_projection),
               mat_inv_view_proj = m_invert(mat_view_proj)) = new(
        vappend(pos, 1),
        vappend(forward, 0),
        vappend(upward, 0),
        vappend(rightward, 0),
        near_clip, far_clip,
        0, 0,
        mat_view, mat_projection, mat_view_proj, mat_inv_view_proj
    )
    UBO_Camera(cam::Cam3D) = UBO_Camera(
        cam.pos,
        let basis = cam_basis(cam)
            tuple(basis.forward, basis.up, basis.right)
        end...,
        min_inclusive(cam.projection.clip_range), max_inclusive(cam.projection.clip_range),
        cam_view_mat(cam), cam_projection_mat(cam)
    )
end
@bp_check(sizeof(UBO_Camera) == sum(sizeof.(fieldtypes(UBO_Camera))),
          "Expected UBO_Camera to be $(sum(sizeof.(fieldtypes(UBO_Camera)))) bytes ",
            "but it was $(sizeof(UBO_Camera))")
let fo = fieldoffset(UBO_Camera, Base.fieldindex(UBO_Camera, :near_clip))
    @bp_check(fo == (16 * 4),
              "Field offset of :near_clip was ", fo)
end
let fo = fieldoffset(UBO_Camera, Base.fieldindex(UBO_Camera, :far_clip))
    @bp_check(fo == (16 * 4) + 4,
              "Field offset of :far_clip was ", fo)
end
let fo = fieldoffset(UBO_Camera, Base.fieldindex(UBO_Camera, :mat_view))
    @bp_check(fo == (16 * 4) + (4 * 4),
              "Field offset of :mat_view was ", fo)
end
const UBO_IDX_CAMERA = 3


################
##   Assets   ##
################

mutable struct Assets
    tex_quit_confirmation::Texture
    prog_lighting::Program

    ubo_buffer_fog::Buffer
    ubo_buffer_sun::Buffer
    ubo_buffer_cam::Buffer
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
        compile_shader_files("post_processing/quad.vert",
                             "post_processing/lighting.frag",
                             insert_above_code = """
                                #define FRAGMENT_DIR 1
                             """,
                             flexible_mode = true)
    )
end

function load_all_buffers()::Tuple
    return tuple(
        # Set each buffer's UBO binding index as it's created.
        let b = Buffer(true, UBO_Fog(0, 0, 0, 0, zero(vRGBf)))
            set_uniform_block(b, UBO_IDX_FOG)
            b
        end,
        let b = Buffer(true, UBO_Light(zero(v3f), zero(vRGBf), Bplus.GL.Ptr_View(), 0, zero(fmat4)))
            set_uniform_block(b, UBO_IDX_LIGHT)
            b
        end,
        let b = Buffer(true, UBO_Camera(zero(v3f), zero(v3f), zero(v3f), zero(v3f),
                                        0, 0,
                                        zero(fmat4), zero(fmat4),
                                        zero(fmat4), zero(fmat4)))
            set_uniform_block(b, UBO_IDX_CAMERA)
            b
        end
    )
end


function Assets()
    textures::Tuple = load_all_textures()
    shaders::Tuple = load_all_shaders()
    buffers::Tuple = load_all_buffers()

    @check_gl_logs("After asset initialization")
    return Assets(textures..., shaders..., buffers...)
end


###################
##   Interface   ##
###################

"The type of sampling used for G-buffer textures in full-screen passes."
const G_BUFFER_SAMPLER = TexSampler{2}(
    wrapping = WrapModes.clamp,
    pixel_filter = PixelFilters.rough,
    mip_filter = nothing
)

function update_buffers(assets::Assets, gui_fog, gui_sun, cam,
                        shadowmap, world_pos_to_sun_texel::fmat4)
    set_buffer_data(assets.ubo_buffer_fog, UBO_Fog(gui_fog))
    set_buffer_data(assets.ubo_buffer_sun, UBO_Light(gui_sun.dir, gui_sun.color,
                                                     shadowmap, @f32(10),
                                                     world_pos_to_sun_texel))
    set_buffer_data(assets.ubo_buffer_cam, UBO_Camera(cam))
end

function prepare_program_lighting( assets::Assets,
                                   tex_depth::Texture,
                                   tex_colors::Texture,
                                   tex_normals::Texture,
                                   tex_surface::Texture,
                                   cam::Cam3D #TODO: Have the camera store and update its own view/projection/etc every "tick"
                                 )
    mat_proj = cam_projection_mat(cam)
    mat_inv_view_proj = m_invert(m_combine(cam_view_mat(cam), mat_proj))

    for uniforms in tuple(
        # For the vertex shader:
        ("u_mat_dirProjection", mat_inv_view_proj),
        ("u_camPosForDir", cam.pos),

        ("u_gBuffer.depth", get_view(tex_depth, G_BUFFER_SAMPLER)),
        ("u_gBuffer.colors", get_view(tex_colors, G_BUFFER_SAMPLER)),
        ("u_gBuffer.normals", get_view(tex_normals, G_BUFFER_SAMPLER)),
        ("u_gBuffer.surface", get_view(tex_surface, G_BUFFER_SAMPLER)),

        ("u_camera.pos", cam.pos),
        ("u_camera.nearClip", min_inclusive(cam.projection.clip_range)),
        ("u_camera.farClip", max_inclusive(cam.projection.clip_range)),
        ("u_camera.forward", cam.forward),
        ("u_camera.up", cam.up),
        ("u_camera.right", cam_rightward(cam)),

        ("u_camera.projectionMat", mat_proj),
        ("u_camera.invViewProjMat", mat_inv_view_proj),
    )
        set_uniform(assets.prog_lighting, uniforms...)
    end

    set_culling(FaceCullModes.off)
    set_depth_writes(false)
    set_depth_test(ValueTests.pass)
    set_blending(make_blend_opaque(BlendStateRGBA))
    set_scissor(nothing)
end

function reload_shaders(assets::Assets)
    shaders = load_all_shaders()
    (assets.prog_lighting, ) = shaders
end