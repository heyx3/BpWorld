mutable struct PostProcess

end

function Base.close(p::PostProcess)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple()
    whitelist = setdiff(fieldnames(typeof(p)), blacklist)
    for field in whitelist
        close(getfield(p, field))
    end
end

function PostProcess(window::GLFW.Window, assets::Assets, scene::Scene)
    return PostProcess()
end


function render(view::PostProcess, window::GLFW.Window, assets::Assets, scene::Scene)
    context::Context = get_context()
    resources::CResources = get_resources(context)

    target_activate(nothing)
    render_clear(context, GL.Ptr_Target(), v4f(1, 0, 1, 0))
    render_clear(context, GL.Ptr_Target(), @f32(1))

    prepare_program_lighting(assets,
        scene.target_tex_depth, scene.target_tex_color,
        scene.target_tex_normals, scene.target_tex_surface,

        scene.sun,
        scene.target_tex_shadowmap, @f32(10),
        scene.sun_viewproj,

        scene.cam,
        scene.fog
    )
    view_activate(get_view(scene.target_tex_shadowmap))
    view_activate(get_view(scene.target_tex_depth, G_BUFFER_SAMPLER))
    view_activate(get_view(scene.target_tex_color, G_BUFFER_SAMPLER))
    view_activate(get_view(scene.target_tex_normals, G_BUFFER_SAMPLER))
    view_activate(get_view(scene.target_tex_surface, G_BUFFER_SAMPLER))
    GL.render_mesh(context, resources.screen_triangle, assets.prog_lighting)
    view_deactivate(get_view(scene.target_tex_shadowmap))
    view_deactivate(get_view(scene.target_tex_depth, G_BUFFER_SAMPLER))
    view_deactivate(get_view(scene.target_tex_color, G_BUFFER_SAMPLER))
    view_deactivate(get_view(scene.target_tex_normals, G_BUFFER_SAMPLER))
    view_deactivate(get_view(scene.target_tex_surface, G_BUFFER_SAMPLER))
end