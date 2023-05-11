#####################
#   Custom Inputs   #
#####################

#TODO: Add these to B+ proper

@bp_axis raw MouseMovement begin
    axis::Int # 1=X, 2=Y
    last_pos::Float32 = zero(Float32)
    current_pos::Float32 = zero(Float32)
    RAW(b, wnd) = (b.current_pos - b.last_pos)
    UPDATE(b, wnd) = let pos = GLFW.GetCursorPos(wnd)
        b.last_pos = b.current_pos
        b.current_pos = getproperty(pos, (:x, :y)[b.axis])
    end
end

function mouse_wheel_changed(axis_mouseWheel, window::GLFW.Window,
                             delta_x::Float64, delta_y::Float64)
    axis_mouseWheel.current_raw -= @f32(delta_y)
end
@bp_axis raw MouseWheel begin
    #TODO: Choose which wheel axis
    MouseWheel(window::GLFW.Window; kw...) = begin
        me = MouseWheel(; kw...)
        GLFW.SetScrollCallback(window, (wnd, dX, dY) -> mouse_wheel_changed(me, wnd, dX, dY))
        return me
    end
    RAW(b) = b.current_raw # Separate callback will update the value
end
#TODO: Add a centralized place in B+ to track current mouse wheel value (e.x. global dict of Context to current wheel pos)


####################
#   World Inputs   #
####################

Base.@kwdef mutable struct SceneInputs
    cam_pitch::AbstractAxis = Axis_MouseMovement(2, scale=-0.05)
    cam_yaw::AbstractAxis = Axis_MouseMovement(1, scale=0.05)
    cam_forward::AbstractAxis = Axis_Key2(GLFW.KEY_W, GLFW.KEY_S)
    cam_rightward::AbstractAxis = Axis_Key2(GLFW.KEY_D, GLFW.KEY_A)
    cam_upward::AbstractAxis = Axis_Key2(GLFW.KEY_E, GLFW.KEY_Q)
    cam_sprint::AbstractButton = Button_Key(GLFW.KEY_LEFT_SHIFT)
    cam_speed_change::AbstractAxis # Set in the constructor to the mouse wheel

    capture_mouse::AbstractButton = Button_Key(GLFW.KEY_SPACE, mode=ButtonModes.just_pressed)
    quit::AbstractButton = Button_Key(GLFW.KEY_ESCAPE, mode=ButtonModes.just_pressed)
    quit_confirm::AbstractButton = Button_Key(GLFW.KEY_ENTER, mode=ButtonModes.just_released)

    reload_shaders::AbstractButton = Button_Key(GLFW.KEY_P, mode=ButtonModes.just_pressed)
end
SceneInputs(window::GLFW.Window; kw...) = SceneInputs(
    cam_speed_change=Axis_MouseWheel(window; scale=-1)
    ;
    kw...
)

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

"Re-usable allocations."
struct SceneCollectionBuffers
    sorted_voxel_layers::Vector{Tuple{Voxels.LayerRenderer, Mesh}}

    SceneCollectionBuffers() = new(
        Vector{Tuple{Voxels.LayerRenderer, Mesh}}()
    )
end


mutable struct World
    voxels::Voxels.Scene
    next_voxels::Optional{Voxels.Scene} # New scene that's currently being generated in the background.

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
    inputs::SceneInputs
    total_seconds::Float32

    g_buffer::Target
    target_tex_depth::Texture
    target_tex_color::Texture  # HDR, RGB is albedo, alpha is emissive strength
    target_tex_surface::Texture # R=Metallic, G=Roughness
    target_tex_normals::Texture #  RGB = signed normal vector

    buffers::SceneCollectionBuffers
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
                sampler = Sampler{2}(
                    wrapping = WrapModes.clamp,
                    pixel_filter = PixelFilters.smooth,
                    mip_filter = PixelFilters.smooth,
                    depth_comparison_mode = ValueTests.LessThanOrEqual
                ))
    )
    return tuple(
        Target(TargetOutput[ ], TargetOutput(tex = textures[1])),
        textures...
    )

end

function World(window::GLFW.Window, assets::Assets)
    window_size::v2i = get_window_size(window)

    # Hard-code the voxel assets to load for now.
    voxel_assets = [
        Voxels.LayerRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "rocks", "rocks.json"),
                                             "r"),
                                        Voxels.LayerData),
                             assets.prog_voxels_depth_only),
        Voxels.LayerRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "scifi", "scifi-blue.json"),
                                             "r"),
                                        Voxels.LayerData),
                             assets.prog_voxels_depth_only),
        Voxels.LayerRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "scifi", "scifi-red.json"),
                                             "r"),
                                        Voxels.LayerData),
                             assets.prog_voxels_depth_only)
    ]

    gui_sun = SunData()
    gui_fog = FogData()
    gui_scene = SceneData()

    # Generate some voxel data.
    voxels = Voxels.Generation.eval_dsl(Meta.parseall(gui_scene.contents))
    voxel_scene = Voxels.Scene(v3i(64, 64, 64), voxels,
                               v3f(10, 10, 10), voxel_assets)

    g_buffer_data = set_up_g_buffer(window_size)
    sun_shadowmap_data = set_up_sun_shadowmap(v2i(1024, 1024))

    check_gl_logs("After world initialization")
    return World(
        voxel_scene,
        nothing,

        #TODO: Save GUI data on close, load it again on start
        gui_sun, init_gui_state(gui_sun),
        gui_fog, init_gui_state(gui_fog),
        gui_scene, init_gui_state(gui_scene),

        m_identityf(4, 4),
        sun_shadowmap_data...,

        Cam3D{Float32}(
            v3f(30, -30, 670),
            vnorm(v3f(1.0, 1.0, -1.0)),
            get_up_vector(),
            Box_minmax(@f32(0.05), @f32(1000)),
            @f32(100),
            @f32(window_size.x / window_size.y)
        ),
        Cam3D_Settings{Float32}(
            move_speed = @f32(50),
            move_speed_min = @f32(5),
            move_speed_max = @f32(100)
        ),
        false, SceneInputs(window), @f32(0.0),

        g_buffer_data...,

        SceneCollectionBuffers()
    )
end


#############
#   Logic   #
#############


"Updates the world."
function update(world::World, delta_seconds::Float32, window::GLFW.Window)
    world.total_seconds += delta_seconds

    # Update inputs.
    if !CImGui.Get_WantCaptureKeyboard(CImGui.GetIO()) &&
       (!world.is_mouse_captured || !CImGui.Get_WantCaptureMouse(CImGui.GetIO()))
    #begin
        for input_names in fieldnames(typeof(world.inputs))
            field_val = getfield(world.inputs, input_names)
            if field_val isa AbstractButton
                Bplus.Input.button_update(field_val, window)
            elseif field_val isa AbstractAxis
                Bplus.Input.axis_update(field_val, window)
            else
                error("Unhandled case: ", typeof(field_val))
            end
        end
        if button_value(world.inputs.capture_mouse)
            world.is_mouse_captured = !world.is_mouse_captured
            GLFW.SetInputMode(
                window, GLFW.CURSOR,
                world.is_mouse_captured ? GLFW.CURSOR_DISABLED : GLFW.CURSOR_NORMAL
            )
        end
    end

    # Update the camera.
    cam_input = Cam3D_Input(
        world.is_mouse_captured,
        axis_value(world.inputs.cam_yaw),
        axis_value(world.inputs.cam_pitch),
        button_value(world.inputs.cam_sprint),
        axis_value(world.inputs.cam_forward),
        axis_value(world.inputs.cam_rightward),
        axis_value(world.inputs.cam_upward),
        axis_value(world.inputs.cam_speed_change)
    )
    (world.cam, world.cam_settings) = cam_update(world.cam, world.cam_settings, cam_input, delta_seconds)

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
                         depth_only_programs::Voxels.LayerDepthRenderer
                        )::Optional{AbstractString}
    # As soon as something fails, roll back the changes and exit.

    # Parse voxel layers.
    local new_layers
    try
        (new_contents, new_layers) = grab_layers(new_contents)
    catch e
        return "Layer error: $(sprint(showerror, e))"
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

    # Load the voxel layers.
    # Failures are mapped to an error message and caught later on.
    local loaded_layers::Dict{Int, Union{Voxels.LayerData, String}}
    loaded_layers = Dict(Iterators.map(new_layers) do (layer_idx, relative_path)
        full_path = joinpath(VOXELS_ASSETS_PATH, relative_path)
        if !isfile(full_path)
            return layer_idx => "File doesn't exist: '$full_path'"
        end
        parsed_data = open(full_path, "r") do f::IO
            try
                return JSON3.read(f, Voxels.LayerData; allow_inf=true)
            catch e
                return "Unable to load '$full_path': $(sprint(showerror, e))"
            end
        end
        return layer_idx => parsed_data
    end)
    # Report failed layers, and if any exist, clean up the other ones that didn't fail.
    failure_msg = nothing
    for (layer_idx, layer_data) in loaded_layers
        if layer_data isa String
            if isnothing(failure_msg)
                failure_msg = "Some layers failed to load:"
            end
            failure_msg = "$failure_msg\n\t$layer_data"
        end
    end
    if exists(failure_msg)
        return failure_msg
    end

    # Generate renderers for each voxel layer.
    layer_renderers = map(sort!(collect(keys(loaded_layers)))) do layer_idx
        layer_data = loaded_layers[layer_idx]
        try
            return Voxels.LayerRenderer(layer_data, depth_only_programs)
        catch e
            return "Layer $layer_idx: $(sprint(showerror, e))"
        end
    end
    failure_msg = nothing
    for layer_renderer in layer_renderers
        if layer_renderer isa String
            if isnothing(failure_msg)
                failure_msg = "Some layers failed to compile:"
            end
            failure_msg = "$failure_msg\n\t$layer_renderer"
        end
    end
    if exists(failure_msg)
        close.(rnd for rnd in layer_renderers if (rnd isa Voxels.LayerRenderer))
        return failure_msg
    end

    # The scene parsed correctly, so kick off its generation.
    if exists(world.next_voxels)
        close(world.next_voxels)
    end
    world.next_voxels = Voxels.Scene(v3i(64, 64, 64), scene_generator,
                                     v3f(10, 10, 10), layer_renderers)
    return nothing
end


"Renders a depth-only pass using the given view/projection matrices."
function render_depth_only(world::World, assets::Assets, mat_viewproj::fmat4)
    set_color_writes(Vec(false, false, false, false))
    set_depth_writes(true)
    set_depth_test(ValueTests.LessThan)
    Voxels.render_depth_only(world.voxels, assets.prog_voxels_depth_only,
                             world.cam, mat_viewproj)
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
    set_culling(context, FaceCullModes.Off)
    set_depth_test(context, ValueTests.LessThan)
    set_scissor(context, nothing)

    # Clear the G-buffer.
    target_activate(world.g_buffer)
    for i in 1:3
        target_clear(world.g_buffer, vRGBAf(0, 0, 0, 0), i)
    end
    target_clear(world.g_buffer, @f32 1.0)

    # Draw the voxels.
    Voxels.render(world.voxels, world.cam, mat_cam_viewproj, world.total_seconds)

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
    mat_sun_proj::fmat4 = m4_ortho(sun_view_min, sun_view_max)
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
end