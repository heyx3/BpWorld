
#########################
##   Uniform buffers   ##
#########################

@std140 struct UniformBlock_Fog
    density::Float32
    dropoff::Float32

    heightOffset::Float32
    heightScale::Float32

    color::vRGBAf # Last component isn't used
end

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

@std140 struct UniformBlock_Sun
    dir::v4f
    color::vRGBAf

    shadowmap::Bplus.GL.gl_type(Bplus.GL.Ptr_View)
    shadow_bias::Float32

    world_to_texel_mat::fmat4
end


########################
##   Buffer Manager   ##
########################

mutable struct SceneRenderBuffers
    #TOOD: Try using one big buffer with different byte ranges
    buf_fog::Bplus.GL.Buffer
    buf_viewport::Bplus.GL.Buffer
    buf_sun::Bplus.GL.Buffer
end

function SceneRenderBuffers()
    buf_fog = Bplus.GL.Buffer(true, sizeof(UniformBlock_Fog))
    set_uniform_block(buf_fog, 1)

    buf_sun = Bplus.GL.Buffer(true, sizeof(UniformBlock_Sun))
    set_uniform_block(buf_sun, 2)

    buf_viewport = Bplus.GL.Buffer(true, sizeof(UniformBlock_Viewport))
    set_uniform_block(buf_viewport, 3)
end
function close(data::SceneRenderBuffers)
    close(data.buf_fog)
    close(data.buf_sun)
    close(data.buf_viewport)
end

function update!(data::SceneRenderBuffers,
                 fog::UniformBlock_Fog, sun::UniformBlock_Sun, view::UniformBlock_Viewport)
    set_buffer_data(data.buf_fog, Ref(fog))
    set_buffer_data(data.buf_viewport, Ref(view))
    set_buffer_data(data.buf_sun, Ref(sun))
end


#######################
##   Buffer Shader   ##
#######################

const SHADER_SNIPPET_WORLD_BUFFERS = string(
    glsl_decl(UniformBlock_Fog, GLSLBlockDecl(
        glsl_name = "u_fog",
        open_gl_name = "UniformBlockFog",
        type = "uniform",
        layout_qualifiers = "binding=0"
    )),
    glsl_decl(UniformBlock_Viewport, GLSLBlockDecl(
        glsl_name = "u_viewport",
        open_gl_name = "UniformBlockViewport",
        type = "uniform",
        layout_qualifiers = "binding=1"
    )),
    glsl_decl(UniformBlock_Sun, GLSLBlockDecl(
        glsl_name = "u_sun",
        open_gl_name = "UniformBlockSun",
        type = "uniform",
        layout_qualifiers = "binding=2"
    ))
)