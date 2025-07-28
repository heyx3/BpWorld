
#########################
##   Uniform buffers   ##
#########################

@std140 struct UniformBlock_Fog
    density::Float32
    dropoff::Float32

    height_offset::Float32
    height_scale::Float32

    color::vRGBAf # Last component isn't used
end
const UBO_IDX_FOG = 1 # Shaders expect this to be set to 1

@std140 struct UniformBlock_Viewport
    pos::v4f
    forward::v4f
    upward::v4f
    rightward::v4f

    near_clip::Float32
    far_clip::Float32

    mat_view::fmat4
    mat_projection::fmat4
    mat_view_proj::fmat4
    mat_inv_view_proj::fmat4
end
UniformBlock_Viewport(cam::Cam3D{Float32}) = UniformBlock_Viewport(
    cam.pos,
    let basis = cam_basis(cam)
      (basis.forward, basis.up, basis.right)
    end...,
    min_inclusive(cam.clip_range),
    max_exclusive(cam.clip_range),
    let m_view = cam_view_mat(cam),
        m_proj = cam_projection_mat(cam),
        m_view_proj = m_combine(m_view, m_proj)
      (m_view, m_proj, m_view_proj, m_invert(m_view_proj))
    end...
)
const UBO_IDX_VIEWPORT = 3 # Shaders expect this to be set to 3

@std140 struct UniformBlock_Sun
    dir::v4f
    color::vRGBAf

    shadowmap::Bplus.GL.gl_type(Bplus.GL.Ptr_View)
    shadow_bias::Float32

    world_to_texel_mat::fmat4
end
const UBO_IDX_SUN = 2 # Shaders expect this to be set to 2


########################
##   Buffer Manager   ##
########################

mutable struct WorldDataBuffers
    #TOOD: Try using one big buffer with different byte ranges; B+ doesn't have its own test for that case
    buf_fog::Bplus.GL.Buffer
    buf_viewport::Bplus.GL.Buffer
    buf_sun::Bplus.GL.Buffer
end
@close_gl_resources(srb::WorldDataBuffers)

function WorldDataBuffers()
    buf_fog = Bplus.GL.Buffer(true, UniformBlock_Fog)
    set_uniform_block(buf_fog, UBO_IDX_FOG)

    buf_sun = Bplus.GL.Buffer(true, UniformBlock_Sun)
    set_uniform_block(buf_sun, UBO_IDX_SUN)

    buf_viewport = Bplus.GL.Buffer(true, UniformBlock_Viewport)
    set_uniform_block(buf_viewport, UBO_IDX_VIEWPORT)

    return WorldDataBuffers(buf_fog, buf_viewport, buf_sun)
end


############################
##   Buffer Shader code   ##
############################

const SHADER_SNIPPET_WORLD_BUFFERS = """
    layout(std140, binding=0) uniform UniformBlockFog {
        $(glsl_decl(UniformBlock_Fog))
    } u_fog;
    layout(std140, binding=1) uniform UniformBlockViewport {
        $(glsl_decl(UniformBlock_Viewport))
    } u_viewport;
    layout(std140, binding=2) uniform UniformBlockSun {
        $(glsl_decl(UniformBlock_Sun))
    } u_sun;
"""