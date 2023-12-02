"A set of textures representing the output of the scene render"
struct ViewportTarget
    color::Optional{Texture}
    emissive::Optional{Texture}
    depth::Texture

    target::Target
end
@close_gl_resources(t::ViewportTarget)

function ViewportTarget(resolution::v2i, depth_only::Bool)
    tex_color = depth_only ? nothing : Texture(
        SimpleFormat(
            FormatTypes.normalized_uint,
            SimpleFormatComponents.RGB,
            SimpleFormatBitDepths.B8
        ),
        resolution
    )
    tex_emissive = depth_only ? nothing : Texture(
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
        depth_only ? [ ] : [ TargetOutput(tex=tex_color), TargetOutput(tex=tex_emissive) ],
        TargetOutput(tex=tex_depth)
    )

    return ViewportTarget(tex_color, tex_emissive, tex_depth, target)
end

function copy_to(src::ViewportTarget, dest::ViewportTarget)
    if exists(src.color) && exists(dest.color)
        copy_tex_pixels(src.color, dest.color)
    end
    if exists(src.emissive) && exists(dest.emissive)
        copy_tex_pixels(src.emissive, dest.emissive)
    end
    copy_tex_pixels(src.depth, dest.depth)
end


mutable struct Viewport
    cam::Cam3D{Float32}
    cam_settings::Cam3D_Settings{Float32}
    size::v2i
    depth_only::Bool

    # Ping-pong between targets as needed (e.x. refractive materials want the result of opaque rendering)
    target_current::ViewportTarget
    target_previous::ViewportTarget
end
@close_gl_resources(v::Viewport, (v.target_current, v.target_previous))

function Viewport(cam::Cam3D{Float32},
                  cam_settings::Cam3D_Settings{Float32},
                  resolution::v2i,
                  depth_only::Bool = false)
    return Viewport(
        cam, cam_settings, resolution, depth_only,
        ViewportTarget(resolution, depth_only),
        ViewportTarget(resolution, depth_only)
    )
end

function viewport_clear(viewport::Viewport)
    if exists(viewport.target_current.color)
        target_clear(viewport.target_current, vRGBAf(0, 0, 0, 1), 1)
    end
    if exists(viewport.target_current.emissive)
        target_clear(viewport.target_current, vRGBAf(0, 0, 0, 1), 2)
    end
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