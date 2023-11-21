"A set of textures representing the output of the scene render"
struct ViewportTarget
    color::Texture
    emissive::Texture
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
    tex_emissive = Texture(
        SimpleFormat(
            FormatTypes.float,
            SimpleFormatComponents.RGB,
            SimpleFormatBitDepths.B16
        ),
        resolution
    )
    tex_depth = Texture(
        DepthStencilFormats.depth_16u
    )

    target = Target(
        [ TargetOutput(tex=tex_color), TargetOutput(tex=tex_emissive) ],
        TargetOutput(tex=tex_depth)
    )

    return ViewportTarget(tex_color, tex_emissive, tex_depth, target)
end

function copy_to(src::ViewportTarget, dest::ViewportTarget)
    copy_tex_pixels(src.color, dest.color)
    copy_tex_pixels(src.emissive, dest.emissive)
    copy_tex_pixels(src.depth, dest.depth)
end


mutable struct Viewport
    cam::Cam3D{Float32}
    cam_settings::Cam3D_Settings{Float32}
    size::v2i

    # Ping-pong between targets as needed (e.x. refractive materials want the result of opaque rendering)
    target_current::ViewportTarget
    target_previous::ViewportTarget
end
@close_gl_resources(v::Viewport, (v.target_current, v.target_previous))

function Viewport(cam::Cam3D{Float32},
                  settings::Cam3D_Settings{Float32},
                  resolution::v2i)
    return Viewport(
        cam, settings, resolution,
        ViewportTarget(resolution), ViewportTarget(resolution)
    )
end

function viewport_clear(viewport::Viewport)
    target_clear(viewport.target_current, vRGBAf(0, 0, 0, 1), 1)
    target_clear(viewport.target_current, vRGBAf(0, 0, 0, 1), 2)
    target_clear(viewport.target_current, @f32(0))
end
function viewport_swap(viewport::Viewport)
    copy_to(viewport.target_current, viewport.target_previous)
end
function viewport_each_target(to_do, viewport::Viewport)
    for target in (viewport.target_current, viewport.target_previous)
        to_do(target)
    end
end