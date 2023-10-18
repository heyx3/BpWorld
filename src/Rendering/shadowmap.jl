"A shadowmap for a directional light"
mutable struct Shadowmap
    # The view-projection matrix for the light's point-of-view.
    mat_view_proj::fmat4
    mat_world_to_texel::fmat4

    depth_texture::Texture
    render_target::Target
end
@close_gl_resources(s::Shadowmap)

function Shadowmap(resolution::Union{Integer, Vec2{<:Integer}},
                   format::E_DepthStencilFormats = DepthStencilFormats.depth_32u)
    resolution = if resolution isa Integer
        v2u(resolution, resolution)
    elseif resolution isa Vec2
        convert(v2u, resolution)
    else
        error(typeof(resolution))
    end

    tex = Texture(
        format,
        resolution,
        sampler = TexSampler{2}(
            wrapping = WrapModes.clamp,
            pixel_filter = PixelFilters.smooth,
            mip_filter = PixelFilters.smooth,
            depth_comparison_mode = ValueTests.less_than_or_equal
        )
    )
    target = Target(TargetOutput(tex=tex))

    return Shadowmap(m4_identityf(), tex, target)
end

"Recalculates the light's projection matrix and clears its shadow-map"
function prepare(shadowmap::Shadowmap,
                 light_dir::v3f,
                 scene_bounds::Box3Df)
    target_clear(shadowmap.target, @f32(1))

    # Calculate an orthogonal view-projection matrix.
    # Reference: https://www.gamedev.net/forums/topic/505893-orthographic-projection-for-shadow-mapping/

    # Calculate a view matrix for the light.
    # It doesn't have a true position, but we can place it at the center of the scene.
    light_world_pos = center(scene_bounds)
    light_world_pos -= light_dir * vlength(size(scene_bounds))
    mat_light_view::fmat4 = m4_look_at(light_world_pos, light_world_pos + light_dir,
                                     get_up_vector())

    # Get the 8 corners of the scene, in the light's view-space.
    scene_corners_world = corners(scene_bounds)
    scene_corners_light_view = m_apply_point.(Ref(mat_light_view), scene_corners_world)

    # Calculate an ortho matrix which covers those corners as tightly as possible.
    light_view_min::v3f = scene_corners_light_view[1]
    light_view_max::v3f = scene_corners_light_view[1]
    for point in tuple(scene_corners_light_view[2:end]..., )
        light_view_min = min(light_view_min, point)
        light_view_max = max(light_view_max, point)
    end
    mat_light_proj::fmat4 = m4_ortho(Box(min=light_view_min, max=light_view_max))

    # Generate the final matrices.
    shadowmap.mat_view_proj = m_combine(mat_light_view, mat_light_proj)
    shadowmap.mat_world_to_texel = m_combine(
        shadowmap.mat_view_proj,
        m_scale(v4f(0.5, 0.5, 0.5, 1.0)),
        m4_translate(v3f(0.5, 0.5, 0.5))
    )
end