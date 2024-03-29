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

function PostProcess(window::GLFW.Window, assets::Assets, world::World)
    return PostProcess()
end


function render(view::PostProcess, window::GLFW.Window, assets::Assets, world::World)
    context::Context = get_context()
    resources::Service_BasicGraphics = service_BasicGraphics()

    target_activate(nothing)
    clear_screen(v4f(1, 0, 1, 0))
    clear_screen(@f32(1))

    prepare_program_lighting(assets,
        world.target_tex_depth, world.target_tex_color,
        world.target_tex_normals, world.target_tex_surface,
        world.cam
    )
    view_activate(get_view(world.target_tex_shadowmap))
    view_activate(get_view(world.target_tex_depth, G_BUFFER_SAMPLER))
    view_activate(get_view(world.target_tex_color, G_BUFFER_SAMPLER))
    view_activate(get_view(world.target_tex_normals, G_BUFFER_SAMPLER))
    view_activate(get_view(world.target_tex_surface, G_BUFFER_SAMPLER))
    render_mesh(resources.screen_triangle, assets.prog_lighting)
    view_deactivate(get_view(world.target_tex_shadowmap))
    view_deactivate(get_view(world.target_tex_depth, G_BUFFER_SAMPLER))
    view_deactivate(get_view(world.target_tex_color, G_BUFFER_SAMPLER))
    view_deactivate(get_view(world.target_tex_normals, G_BUFFER_SAMPLER))
    view_deactivate(get_view(world.target_tex_surface, G_BUFFER_SAMPLER))
end