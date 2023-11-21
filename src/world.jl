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
                    )::Tuple{typeof(contents),
                             Dict{VoxelElement, typeof(contents)}}
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
    renderer::Renderer.Scene
    main_viewport::Renderer.Viewport

    sun::SunData
    sun_gui::SunDataGui
    fog::FogData
    fog_gui::FogDataGui
    scene::SceneData
    scene_gui::SceneDataGui

    is_mouse_captured::Bool
    total_seconds::Float32
end
function Base.close(s::World)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple(:total_seconds,
                      :sun, :sun_gui, :fog, :fog_gui, :scene, :scene_gui,
                      :cam, :cam_settings, :is_mouse_captured, :total_seconds)
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
        clip_range=IntervalF(min=0.05, max=1000),
        fov_degrees=@f32(100),
        aspect_width_over_height=@f32(window_size.x / window_size.y)
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

        false, @f32(0.0)
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
    begin_scene_frame(
        world.renderer, delta_seconds, world.total_seconds,
        (
            dir = world.sun.dir,
            color = world.sun.color,
            shadow_bias = @f32(10)
        ),
        UniformBlock_Fog(
            world.fog.density, world.fog.dropoff,
            world.fog.height_offset, world.fog.height_scale,
            vappend(world.fog.color, 1);
        )
    )
end

"
Processes a new scene file in the background, eventually replacing the current scene with it.
If the scene file is invalid, returns an error message.
Otherwise, returns `nothing` to indicate that it was accepted.
"
function start_new_scene(renderer::Renderer.Scene, new_contents::AbstractString,
                         voxel_resolution::v3i
                        )::Optional{AbstractString}
    # As soon as something fails, roll back the changes and exit.

    # Parse voxel layers.
    local new_layers::Dict{VoxelElement, AbstractString}
    try
        (new_contents, new_layers) = grab_layers(new_contents)
    catch e
        return "Layer error: $(sprint(showerror, e))"
    end
    ordered_layers = sort!(collect(layers_by_id), by=kvp->kvp[1])
    layer_list::Vector = map(1:maximum(keys(ordered_layers))) do i::Int
        get(ordered_layers, i, Rendering.ERROR_LAYER_FILE)
    end

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

    # Everything loaded and parsed correctly, so kick off the scene generation.
    reset_scene(renderer, voxel_generator, layer_list, voxel_resolution)

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

    Rendering.render_viewport(
        world.renderer, world.main_viewport,
        world.total_seconds,
        RenderSettings(
            render_sky = true
        )
    )

    end_scene_frame(world.renderer)

    # Copy the render to the screen with an adjusted gamma.
    target_activate(nothing)
    simple_blit(
        world.main_viewport.target_current.color
        ;
        output_curve=@f32(1 / 2.2)
    )
end

function on_window_resized(world::World, window::GLFW.Window, new_size::v2i)
    if new_size != world.main_viewport.size
        remove_viewport(world.renderer, world.main_viewport)
        world.main_viewport = add_viewport(
            world.renderer,
            let c = world.main_viewport.cam
                @set! c.aspect_width_over_height = @f32(new_size.x) / @f32(new_size.y)
                c
            end,
            world.main_viewport.cam_settings
            ;
            resolution = new_size
        )
    end
end