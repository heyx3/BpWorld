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


#############
#   World   #
#############

mutable struct World
    renderer::Rendering.Scene
    main_viewport::Rendering.Viewport

    #TODO: Add a suffix like "_ubo" to the UBO structs!!
    sun::SunData
    sun_gui::SunDataGui
    fog::FogData
    fog_gui::FogDataGui
    scene::SceneData
    scene_gui::SceneDataGui

    ubo_fog::UniformBlock_Fog

    is_mouse_captured::Bool
    total_seconds::Float32
    last_render_timestamp::Float32
end
Base.close(w::World) = close.([
    w.renderer
])

function World(window::GLFW.Window, assets::Assets)
    window_size::v2i = get_window_size(window)

    gui_sun = SunData()
    gui_fog = FogData()
    gui_scene = SceneData()

    configure_inputs()

    renderer = Rendering.Scene()
    check_gl_logs("After renderer initialization")

    main_camera = Cam3D{Float32}(
        pos=v3f(30, -30, 670),
        forward=vnorm(v3f(1, 1, -0.2)),
        projection = PerspectiveProjection{Float32}(
            clip_range=IntervalF(min=0.05, max=1000),
            vertical_fov_degrees=@f32(100),
            aspect_width_over_height=@f32(window_size.x / window_size.y)
        )
    )
    main_camera_settings = Cam3D_Settings{Float32}(
        move_speed=@f32(50),
        move_speed_min=@f32(5),
        move_speed_max=@f32(100)
    )
    main_viewport = Rendering.add_viewport(
        renderer,
        main_camera, main_camera_settings
        ;
        resolution=window_size
    )
    check_gl_logs("After viewport initialization")

    # Start generating some voxel data.
    error_string = start_new_scene(renderer, gui_scene.contents, v3i(64, 64, 64))
    if exists(error_string)
        error("Screwed up inital scene file! ", error_string)
    end

    check_gl_logs("After world initialization")
    return World(
        renderer,
        main_viewport,

        #TODO: Save GUI data on close, load it again on start
        gui_sun, init_gui_state(gui_sun),
        gui_fog, init_gui_state(gui_fog),
        gui_scene, init_gui_state(gui_scene),

        UniformBlock_Fog(gui_fog.density, gui_fog.dropoff,
                         gui_fog.height_offset, gui_fog.height_scale,
                         vappend(gui_fog.color, 1.0f0)),

        false, @f32(0.0), @f32(0.0)
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
    (world.main_viewport.cam, world.main_viewport.cam_settings) = cam_update(
        world.main_viewport.cam,
        world.main_viewport.cam_settings,
        cam_input, delta_seconds
    )

    # Update the renderer.
    world.ubo_fog.density = world.fog.density
    world.ubo_fog.dropoff = world.fog.dropoff
    world.ubo_fog.height_offset = world.fog.height_offset
    world.ubo_fog.height_scale = world.fog.height_scale
    world.ubo_fog.color = vappend(world.fog.color, 1.0f0)
end

"Renders the world, usually to the screen."
function render(world::World, assets::Assets, display_to_screen::Bool)
    begin_scene_frame(
        world.renderer,
        world.total_seconds - world.last_render_timestamp,
        world.total_seconds,
        (dir=world.sun.dir, color=world.sun.color, shadow_bias=@f32(0.0)),
        world.ubo_fog
    )
    render_viewport(
        world.renderer, world.main_viewport,
        world.total_seconds,
        RenderSettings(
            render_sky = true
        )
    )
    end_scene_frame(world.renderer)

    if display_to_screen
        target_activate(nothing)
        simple_blit(world.main_viewport.target_current.color)
    end
end

function on_window_resized(world::World, window::GLFW.Window, new_size::v2i)
    if new_size != world.main_viewport.size
        remove_viewport(world.renderer, world.main_viewport)
        world.main_viewport = add_viewport(
            world.renderer,
            let c = world.main_viewport.cam
              @set! c.projection.aspect_width_over_height = @f32(new_size.x) / @f32(new_size.y)
              c
            end,
            world.main_viewport.cam_settings
            ;
            resolution = new_size
        )
    end
end