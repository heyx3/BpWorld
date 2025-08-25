function get_shadowmap_transform(light_dir::v3f,
                                 scene_bounds::Box3Df
                                )::@NamedTuple{cam::Cam3D{Float32}, view_proj::fmat4, world_to_texel::fmat4}
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
    ortho_box = Box(min=light_view_min, max=light_view_max)
    mat_light_proj::fmat4 = m4_ortho(ortho_box)

    # Generate the final matrices.
    mat_view_proj = m_combine(mat_light_view, mat_light_proj)
    mat_world_to_texel = m_combine(
        mat_view_proj,
        m_scale(v4f(0.5, 0.5, 0.5, 1.0)),
        m4_translate(v3f(0.5, 0.5, 0.5))
    )
    return (
        cam = Cam3D{Float32}(
            pos=light_world_pos,
            forward=light_dir,
            projection = ortho_box
        ),
        view_proj=mat_view_proj,
        world_to_texel=mat_world_to_texel
    )
end