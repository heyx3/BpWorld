mutable struct Sky
    shader::Bplus.GL.Program
    sun_emissive_strength::Float32
end
@close_gl_resources(s::Sky)


const SKY_SHADER_VERT = """
    //Expects to use the full-screen triangle or quad in the 'BasicGraphics' service.
    //Those vertices are provided in 2D NDC space.
    in vec2 vIn_corner;

    out vec2 fIn_uv;

    void main() {
        fIn_uv = 0.5 + (0.5 * vIn_corner);

        vec3 posNDC = vec3(vIn_corner, 1.0);
        gl_Position = vec4(posNDC, 1.0);
    }
"""
const SKY_SHADER_FRAG = """
    $(LayerShaders.UTILS_INCLUDES)
    $(LayerShaders.FRAG_SHADER_OUTPUTS)
    uniform float $(LayerShaders.UNIFORM_ELAPSED_SECONDS);
    #line 0

    uniform float u_emissiveBrightness = 1.0;
    in vec2 fIn_uv;

    void main() {
        //Compute the direction this fragment is looking at.
        //The fragment's depth is guaranteed to be 1.0 already.
        vec3 ndcPos = -1.0 + (2.0 * vec3(fIn_uv, 1.0));
        vec4 worldPos4 = u_cam.matInvViewProj * vec4(ndcPos, 1.0);
        vec3 worldPos = worldPos4.xyz / worldPos4.w;
        vec3 skyDir = normalize(worldPos - u_cam.pos.xyz);

        //Color the sky based on the look direction.
        vec3 reflectedColor = vec3(0.8, 0.825, 1.0) +
                              pow(max(0.0, dot(u_sun.dir.xyz, -skyDir)),
                                  256.0);

        //Write to the forward-rendering attachments.
        fOut_color = reflectedColor;
        fOut_emission = reflectedColor * u_emissiveBrightness;
    }
"""

Sky() = new(
    Program(SKY_SHADER_VERT, SKY_SHADER_FRAG),
    @f32(10) # Sun emissive brightness
)

function render_sky(sky::Sky, total_elapsed_seconds::Float32)
    set_uniform(sky.shader, LayerShaders.UNIFORM_ELAPSED_SECONDS, total_elapsed_seconds)
    set_uniform(sky.shader, "u_emissiveBrightness", sky.sun_emissive_strength)
    render_mesh(service_BasicGraphics().screen_triangle, sky.shader)
end