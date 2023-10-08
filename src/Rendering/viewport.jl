"A set of textures representing the output of the scene render"
struct ViewportTarget
    color::Texture
    emissive_strength::Texture
    depth::Texture

    target::Target
end
@close_gl_resources(t::ViewportTarget)

function ViewportTarget(resolution::v2i)
    tex_color = Texture(
        SimpleFormat(
            FormatTypes.normalized_uint,
            SimpleFormatComponents.RGB,
            SimpleFormatBitDepths.B8
        ),
        resolution
    )
    tex_emission = Texture(
        SimpleFormat(
            FormatTypes.float,
            SimpleFormatComponents.R,
            SimpleFormatBitDepths.B16
        ),
        resolution
    )
    tex_depth = Texture(
        DepthStencilFormats.depth_16u
    )

    target = Target(
        [ TargetOutput(tex=tex_color), TargetOutput(tex=tex_emission) ],
        TargetOutput(tex=tex_depth)
    )

    return ViewportTarget(tex_color, tex_emission, tex_depth, target)
end


mutable struct Viewport
    cam::Cam3D{Float32}
    cam_settings::Cam3D_Settings{Float32}

    # Ping-pong between targets as needed (e.x. refractive materials want the result of opaque rendering)
    target_current::ViewportTarget
    target_previous::ViewportTarget
end
@close_gl_resources(v::Viewport, (v.target_current, v.target_previous))

function Viewport(cam::Cam3D{Float32},
                  settings::Cam3D_Settings{Float32}
                  resolution::v2i = Bplus.GL.get_window_size())
    return Viewport(
        cam, settings,
        ViewportTarget(resolution), ViewportTarget(resolution)
    )
end

function viewport_clear(viewport::Viewport)
    target_clear(viewport.target_current, )
end
function viewport_swap(viewport::Viewport)
    error("#TODO: Add Copy-texture operation in B+, then use it here")

    old_current = viewport.target_current
    viewport.target_current = viewport.target_previous
    viewport.target_previous = old_current
end