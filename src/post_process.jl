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
    prepare_program_lighting(assets, scene.target_tex_depth, scene.target_tex_color,
                                     scene.target_tex_normals, scene.target_tex_surface,
                                     vnorm(v3f(1, 1, -1)), one(v3f)*1, scene.cam)
    view_activate(get_view(scene.target_tex_depth, G_BUFFER_SAMPLER))
    view_activate(get_view(scene.target_tex_color, G_BUFFER_SAMPLER))
    view_activate(get_view(scene.target_tex_normals, G_BUFFER_SAMPLER))
    view_activate(get_view(scene.target_tex_surface, G_BUFFER_SAMPLER))
    GL.render_mesh(context, resources.screen_triangle, assets.prog_lighting)
    view_deactivate(get_view(scene.target_tex_depth, G_BUFFER_SAMPLER))
    view_deactivate(get_view(scene.target_tex_color, G_BUFFER_SAMPLER))
    view_deactivate(get_view(scene.target_tex_normals, G_BUFFER_SAMPLER))
    view_deactivate(get_view(scene.target_tex_surface, G_BUFFER_SAMPLER))
end