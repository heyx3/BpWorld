"A set of textures representing the output of the scene render, possibly depth-only"
struct ViewportTarget
    color::Optional{Texture}
    emissive::Optional{Texture}
    depth::Texture

    target::Target
    target_all_color_attachments::Vector{Int}
end
@close_gl_resources(t::ViewportTarget)

#TODO: Option to remove mips (mips are currently only needed for the shadowmap viewport)
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
        DepthStencilFormats.depth_16u,
        resolution
    )

    target = Target(
        depth_only ? [ ] : [ TargetOutput(tex=tex_color), TargetOutput(tex=tex_emissive) ],
        TargetOutput(tex=tex_depth)
    )

    return ViewportTarget(
        tex_color, tex_emissive,
        tex_depth, target,
        depth_only ? [ ] : [ 1, 2 ]
    )
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

function viewport_clear(vt::ViewportTarget)
    # Clear color buffers.
    target_configure_fragment_outputs(vt.target, vt.target_all_color_attachments)
    for i in vt.target_all_color_attachments
        target_clear(vt.target, vRGBAf(0, 0, 0, 0), i)
    end
    # Clear depth buffer.
    target_clear(vt.target, @f32(1))
end

function viewport_activate_samplers(vt::ViewportTarget)
    for tex in (vt.color, vt.emissive, vt.depth)
        view_activate(tex)
    end
end
function viewport_deactivate_samplers(vt::ViewportTarget)
    for tex in (vt.color, vt.emissive, vt.depth)
        view_deactivate(tex)
    end
end


mutable struct Viewport
    cam::Cam3D{Float32}
    cam_settings::Cam3D_Settings{Float32}
    size::v2i
    depth_only::Bool # If true, target textures are all null except for Depth.

    # This is *not* a ping-pong rendering setup; instead the contents of "current" are copied back to "previous"
    #    whenever a new render layer wants to sample the outputs of all previous ones,
    #    e.g. refractive shaders sampling from opaque surfaces.
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
    viewport_clear(viewport.target_current)
end
function viewport_swap(viewport::Viewport)
    copy_to(viewport.target_current, viewport.target_previous)
end
function viewport_each_target(to_do, viewport::Viewport)
    for target in (viewport.target_current, viewport.target_previous)
        to_do(target)
    end
end