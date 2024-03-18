####################
#   World Inputs   #
####################

"Configures this game's inputs within the already-created `InputService``."
function configure_inputs()
    # Buttons:
    create_button("cam_sprint",
                  ButtonInput(GLFW.KEY_LEFT_SHIFT))
    create_button("capture_mouse",
                  ButtonInput(GLFW.KEY_SPACE, ButtonModes.just_pressed))
    create_button("quit",
                  ButtonInput(GLFW.KEY_ESCAPE, ButtonModes.just_pressed))
    create_button("quit_confirm",
                  ButtonInput(GLFW.KEY_ENTER, ButtonModes.just_pressed))
    create_button("reload_shaders",
                  ButtonInput(GLFW.KEY_P, ButtonModes.just_pressed))

    # Axes:
    create_axis("cam_pitch",
                AxisInput(MouseAxes.y, AxisModes.delta; value_scale=-0.05))
    create_axis("cam_yaw",
                AxisInput(MouseAxes.x, AxisModes.delta; value_scale=0.05))
    create_axis("cam_forward",
                AxisInput([ ButtonAsAxis(GLFW.KEY_W), ButtonAsAxis_Negative(GLFW.KEY_S) ]))
    create_axis("cam_rightward",
                AxisInput([ ButtonAsAxis(GLFW.KEY_D), ButtonAsAxis_Negative(GLFW.KEY_A) ]))
    create_axis("cam_upward",
                AxisInput([ ButtonAsAxis(GLFW.KEY_E), ButtonAsAxis_Negative(GLFW.KEY_Q) ]))
    create_axis("cam_speed_change",
                AxisInput(MouseAxes.scroll_y, AxisModes.delta; value_scale=-1))
end

# Short-hand for each input:
input_cam_turn() = v2f(get_axis("cam_yaw"), get_axis("cam_pitch"))
input_cam_move() = v3f(get_axis("cam_rightward"), get_axis("cam_forward"), get_axis("cam_upward"))
input_cam_sprint() = get_button("cam_sprint")
input_cam_speed_change() = get_axis("cam_speed_change")
input_capture_mouse() = get_button("capture_mouse")
input_quit() = get_button("quit")
input_quit_confirm() = get_button("quit_confirm")
input_reload_shaders() = get_button("reload_shaders")


####################
#   Layer parsing  #
####################

"
Grabs the `#layer N path/to/layer.json` statements from the given scene file.
Returns the scene file with those statements stripped (leaving only the DSL),
    and the contents of those statements.
"
function grab_layers(contents::AbstractString
                    )::Tuple{AbstractString,
                             Dict{VoxelElement, AbstractString}}
    layers = Dict{VoxelElement, AbstractString}()
    rgx = r"(?m)^#layer\s+([0-9]+)\s+(.+)$"
    for match in eachmatch(rgx, contents)
        (layer_idx, layer_relative_path) = match.captures
        layer_idx = parse(VoxelElement, layer_idx)
        @bp_check(!haskey(layers, layer_idx),
                  "Layer ", layer_idx, " is named more than once: ",
                    "\"", layer_relative_path, "\" and then \"",
                    layers[layer_idx], "\"")
        layers[layer_idx] = layer_relative_path
    end
    return (replace(contents, rgx=>""), layers)
end


#############
#   World   #
#############

mutable struct World
    voxels::Voxels.Scene
    next_voxels::Optional{Voxels.Scene} # New scene that's currently being generated in the background.
    voxel_materials::Voxels.RendererCache

    sun::SunData
    sun_gui::SunDataGui

    fog::FogData
    fog_gui::FogDataGui

    scene::SceneData
    scene_gui::SceneDataGui

    sun_viewproj::fmat4 # Updated every frame
    target_shadowmap::Target
    target_tex_shadowmap::Texture

    cam::Cam3D
    cam_settings::Cam3D_Settings
    is_mouse_captured::Bool
    total_seconds::Float32

    g_buffer::Target
    target_tex_depth::Texture
    target_tex_color::Texture  # HDR, RGB is albedo, alpha is emissive strength
    target_tex_surface::Texture # R=Metallic, G=Roughness
    target_tex_normals::Texture #  RGB = signed normal vector
end
function Base.close(s::World)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple(:total_seconds,
                      :sun_viewproj,
                      :sun, :sun_gui, :fog, :fog_gui, :scene, :scene_gui,
                      :cam, :cam_settings, :is_mouse_captured, :inputs,
                      :buffers)
    whitelist = setdiff(fieldnames(typeof(s)), blacklist)
    for field in whitelist
        v = getfield(s, field)
        if v isa AbstractVector
            for el in v
                close(el)
            end
            empty!(v)
        elseif exists(v) # Some fields are Optional
            close(v)
        end
    end
end

function set_up_g_buffer(size::v2i)::Tuple
    textures = tuple(
        #TODO: Try lowering these until the quality is noticeably affected.
        Texture(DepthStencilFormats.depth_32u, size),
        Texture(SimpleFormat(FormatTypes.float,
                             SimpleFormatComponents.RGBA,
                             SimpleFormatBitDepths.B32),
                size),
        Texture(SimpleFormat(FormatTypes.normalized_uint,
                             SimpleFormatComponents.RG,
                             SimpleFormatBitDepths.B8),
                size),
        Texture(SimpleFormat(FormatTypes.normalized_int,
                             SimpleFormatComponents.RGB,
                             SimpleFormatBitDepths.B8),
                size)
    )
    return tuple(
        Target(
            [TargetOutput(tex = t) for t in textures[2:end]],
            TargetOutput(tex = textures[1])
        ),
        textures...
    )
end
function set_up_sun_shadowmap(size::v2i)::Tuple
    textures = tuple(
        Texture(DepthStencilFormats.depth_32u, size,
                sampler = TexSampler{2}(
                    wrapping = WrapModes.clamp,
                    pixel_filter = PixelFilters.smooth,
                    mip_filter = PixelFilters.smooth,
                    depth_comparison_mode = ValueTests.less_than_or_equal
                ))
    )
    return tuple(
        Target(TargetOutput[ ], TargetOutput(tex = textures[1])),
        textures...
    )

end

function World(window::GLFW.Window, assets::Assets)
    window_size::v2i = get_window_size(window)

    gui_sun = SunData()
    gui_fog = FogData()
    gui_scene = SceneData()

    configure_inputs()

    # Generate some voxel data.
    # Parse voxel layers.
    (scene_dsl, layers_by_id) = grab_layers(gui_scene.contents)
    scene_dsl_expr = Meta.parseall(scene_dsl)
    voxel_generator = Voxels.Generation.eval_dsl(scene_dsl_expr)
    if voxel_generator isa Voxels.Generation.DslError
        error("Failed to compile initial default voxel scene: ", sprint(showerror, voxel_generator))
    elseif !isa(voxel_generator, Voxels.Generation.AbstractVoxelGenerator)
        error("Unexpected output of voxel scene compilation: ", voxel_generator)
    end
    voxel_scene = Voxels.Scene(v3i(64, 64, 64), voxel_generator,
                               map(kvp -> kvp[2],
                                   sort!(collect(layers_by_id), by=kvp->kvp[1])),
                               v3f(10, 10, 10))

    voxel_materials = RendererCache()

    g_buffer_data = set_up_g_buffer(window_size)
    sun_shadowmap_data = set_up_sun_shadowmap(v2i(1024, 1024))

    check_gl_logs("After world initialization")
    return World(
        voxel_scene,
        nothing,
        voxel_materials,

        #TODO: Save GUI data on close, load it again on start
        gui_sun, init_gui_state(gui_sun),
        gui_fog, init_gui_state(gui_fog),
        gui_scene, init_gui_state(gui_scene),

        m_identityf(4, 4),
        sun_shadowmap_data...,

        Cam3D{Float32}(
            pos=v3f(30, -30, 670),
            forward=vnorm(v3f(1, 1, -0.2)),
            clip_range=IntervalF(min=0.05, max=1000),
            fov_degrees=@f32(100),
            aspect_width_over_height=@f32(window_size.x / window_size.y)
        ),
        Cam3D_Settings{Float32}(
            move_speed=@f32(50),
            move_speed_min=@f32(5),
            move_speed_max=@f32(100)
        ),
        false, @f32(0.0),

        g_buffer_data...
    )
end


#############
#   Logic   #
#############


"Updates the world."
function update(world::World, delta_seconds::Float32, window::GLFW.Window)
    world.total_seconds += delta_seconds

    # Update inputs.
    if !unsafe_load(CImGui.GetIO().WantCaptureKeyboard) &&
       (!world.is_mouse_captured || !unsafe_load(CImGui.GetIO().WantCaptureMouse))
    #begin
        if input_capture_mouse()
            world.is_mouse_captured = !world.is_mouse_captured
            GLFW.SetInputMode(
                window, GLFW.CURSOR,
                world.is_mouse_captured ? GLFW.CURSOR_DISABLED : GLFW.CURSOR_NORMAL
            )
        end
    end

    # Update the camera.
    cam_turn = input_cam_turn()
    cam_move = input_cam_move()
    cam_input = Cam3D_Input(
        controlling_rotation=world.is_mouse_captured,
        yaw=cam_turn.x,
        pitch=cam_turn.y,
        boost=input_cam_sprint(),
        forward=cam_move.y,
        right=cam_move.x,
        up=cam_move.z,
        speed_change=input_cam_speed_change()
    )
    (world.cam, world.cam_settings) = cam_update(world.cam, world.cam_settings, cam_input, delta_seconds)

    # Update cached disk assets.
    Voxels.check_disk_modifications!(world.voxel_materials)

    # Update the scene.
    Voxels.update(world.voxels, delta_seconds)
    # See if the next scene is finished loading, and if so, replace the current scene.
    if exists(world.next_voxels)
        Voxels.update(world.next_voxels, delta_seconds)
        if world.next_voxels.is_finished_setting_up
            close(world.voxels)
            world.voxels = world.next_voxels
            world.next_voxels = nothing
        end
    end
end

"
Processes a new scene file in the background, eventually replacing the current scene with it.
If the scene file is invalid, returns an error message.
Otherwise, returns `nothing` to indicate that it was accepted.
"
function start_new_scene(world::World, new_contents::AbstractString,
                        )::Optional{AbstractString}
    # As soon as something fails, roll back the changes and exit.

    # Parse voxel layers.
    local new_layers::Dict{VoxelElement, AbstractString}
    try
        (new_contents, new_layers) = grab_layers(new_contents)
    catch e
        return "Layer error: $(sprint(showerror, e))"
    end
    layer_names = map(kvp -> kvp[2],
                      sort!(collect(new_layers),
                            by=kvp->kvp[1]))

    # Parse voxel generator.
    local scene_expr
    try
        scene_expr = Meta.parseall(new_contents)
    catch e
        return "Scene has invalid syntax $(sprint(showerror, e))"
    end

    # Evaluate the voxel generator expression.
    scene_generator = Voxels.Generation.eval_dsl(scene_expr)
    if scene_generator isa Voxels.Generation.DslError
        return string(scene_generator.msg_data...)
    elseif !isa(scene_generator, Voxels.Generation.AbstractVoxelGenerator)
        return "Output of the scene is not a voxel generator! It's a $(typeof(scene_generator))"
    end

    # Everything loaded parsed correctly, so kick off the scene generation.
    if exists(world.next_voxels)
        close(world.next_voxels)
    end
    world.next_voxels = Voxels.Scene(v3i(64, 64, 64), scene_generator,
                                     layer_names,
                                     v3f(10, 10, 10))
    return nothing
end


"Renders a depth-only pass using the given view/projection matrices."
function render_depth_only(world::World, assets::Assets, mat_viewproj::fmat4)
    set_color_writes(Vec(false, false, false, false))
    set_depth_writes(true)
    set_depth_test(ValueTests.less_than)
    Voxels.render_depth_only(world.voxels, mat_viewproj, world.voxel_materials)
    set_color_writes(Vec(true, true, true, true))
end

"Renders the world."
function render(world::World, assets::Assets)
    context::Context = get_context()

    # Calculate camera matrices.
    mat_cam_view::fmat4 = cam_view_mat(world.cam)
    mat_cam_proj::fmat4 = cam_projection_mat(world.cam)
    mat_cam_viewproj::fmat4 = m_combine(mat_cam_view, mat_cam_proj)
    mat_cam_inv_view::fmat4 = m_invert(mat_cam_view)
    mat_cam_inv_proj::fmat4 = m_invert(mat_cam_proj)
    mat_cam_inv_viewproj::fmat4 = m_invert(mat_cam_viewproj)

    # Set up render state.
    set_depth_writes(context, true) # Needed to clear the depth buffer
    set_color_writes(context, vRGBA{Bool}(true, true, true, true))
    set_blending(context, make_blend_opaque(BlendStateRGBA))
    set_culling(context, FaceCullModes.off)
    set_depth_test(context, ValueTests.less_than)
    set_scissor(context, nothing)

    # Clear the G-buffer.
    target_activate(world.g_buffer)
    for i in 1:3
        target_clear(world.g_buffer, vRGBAf(0, 0, 0, 0), i)
    end
    target_clear(world.g_buffer, @f32 1.0)

    # Draw the voxels.
    Voxels.render(world.voxels, mat_cam_viewproj,
                  world.total_seconds, world.voxel_materials)

    # Calculate an orthogonal view-projection matrix for the sun's shadow-map.
    # Reference: https://www.gamedev.net/forums/topic/505893-orthographic-projection-for-shadow-mapping/
    #TODO: Bound with the entire world, to catch shadow casters that are outside the frustum
    # Get the frustum points in world space:
    frustum_points_ndc::NTuple{8, v3f} = (
        v3f(-1, -1, -1),
        v3f(-1, -1, 1),
        v3f(-1, 1, -1),
        v3f(-1, 1, 1),
        v3f(1, -1, -1),
        v3f(1, -1, 1),
        v3f(1, 1, -1),
        v3f(1, 1, 1),
    )
    frustum_points_world = m_apply_point.(Ref(mat_cam_inv_viewproj), frustum_points_ndc)
    frustum_world_center = @f32(1/8) * ((frustum_points_world[1] + frustum_points_world[2]) +
                                        (frustum_points_world[3] + frustum_points_world[4]) +
                                        (frustum_points_world[5] + frustum_points_world[6]) +
                                        (frustum_points_world[7] + frustum_points_world[8]))
    voxels_world_range = world.voxels.world_scale * vsize(world.voxels.grid)
    voxels_world_center = voxels_world_range / v3f(Val(2))
    # Make a view matrix for the sun looking at that frustum:
    sun_world_pos = voxels_world_center
    @set! sun_world_pos -= world.sun.dir * max_exclusive(world.cam.clip_range)
    mat_sun_view::fmat4 = m4_look_at(sun_world_pos, sun_world_pos + world.sun.dir,
                                     get_up_vector())
    # Get the bounds of the frustum in the sun's view space:
    frustum_points_sun_view = m_apply_point.(Ref(mat_sun_view), frustum_points_world)
    voxel_points_world = tuple((
        voxels_world_range * v3f(t...)
          for t in Iterators.product(0:1, 0:1, 0:1)
    )...)
    voxel_points_sun_view = m_apply_point.(Ref(mat_sun_view), voxel_points_world)
    sun_view_min::v3f = voxel_points_sun_view[1]
    sun_view_max::v3f = voxel_points_sun_view[1]
    for point in tuple(voxel_points_sun_view[2:end]..., )#frustum_points_sun_view...)
        sun_view_min = min(sun_view_min, point)
        sun_view_max = max(sun_view_max, point)
    end
    mat_sun_proj::fmat4 = m4_ortho(Box(min=sun_view_min, max=sun_view_max))
    world.sun_viewproj = m_combine(mat_sun_view, mat_sun_proj)
    mat_sun_world_to_texel = m_combine(
        world.sun_viewproj,
        m_scale(v4f(0.5, 0.5, 0.5, 1.0)),
        m4_translate(v3f(0.5, 0.5, 0.5))
    )

    # Render the sun's shadow-map.
    target_activate(world.target_shadowmap)
    target_clear(world.target_shadowmap, @f32 1.0)
    render_depth_only(world, assets, world.sun_viewproj)
    target_activate(nothing)
    glGenerateTextureMipmap(get_ogl_handle(world.target_tex_shadowmap))
end

function on_window_resized(world::World, window::GLFW.Window, new_size::v2i)
    if new_size != world.g_buffer.size
        close.((world.g_buffer, world.target_tex_depth,
                world.target_tex_color, world.target_tex_normals,
                world.target_tex_surface))
        new_data = set_up_g_buffer(new_size)
        (
            world.g_buffer,
            world.target_tex_depth,
            world.target_tex_color,
            world.target_tex_surface,
            world.target_tex_normals
        ) = new_data
    end

    cam = world.cam
    @set! cam.aspect_width_over_height = @f32(new_size.x) / @f32(new_size.y)
    world.cam = cam
end