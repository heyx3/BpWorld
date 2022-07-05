@bp_axis signed MouseWheel begin
    #TODO: Choose which wheel axis
    MouseWheel(window::GLFW.Window) = begin
        me = MouseWheel()
        GLFW.SetScrollCallback(window, (wnd, dX, dY) -> mouse_wheel_changed(me, wnd, dX, dY))
        return me
    end
    RAW(b) = b.current_raw # Separate callback will update the value
end
#TODO: Add a centralized place in B+ to track current mouse wheel value (e.x. global dict of Context to current wheel pos)
function mouse_wheel_changed(controls::Axis_MouseWheel, window::GLFW.Window,
                             delta_x::Float64, delta_y::Float64)
    controls.current_raw += @f32(delta_y)
end

Base.@kwdef mutable struct SceneInputs
    cam_forward::AbstractAxis = Axis_Key2(GLFW.KEY_S, GLFW.KEY_W)
    cam_rightward::AbstractAxis = Axis_Key2(GLFW.KEY_A, GLFW.KEY_D)
    cam_upward::AbstractAxis = Axis_Key2(GLFW.KEY_Q, GLFW.KEY_E)
    cam_sprint::AbstractButton = Button_Key(GLFW.KEY_LEFT_SHIFT)
    cam_speed_change::AbstractAxis # Set in the constructor to the mouse wheel
    quit::AbstractButton = Button_Key(GLFW.KEY_ESCAPE, mode=ButtonModes.just_pressed)
    quit_confirm::AbstractButton = Button_Key(GLFW.KEY_ENTER, mode=ButtonModes.just_pressed)
end
SceneInputs(window::GLFW.Window; kw...) = SceneInputs(cam_speed_change=Axis_MouseWheel(window), kw...)

mutable struct Scene
    mesh_voxel_vertices::Buffer
    mesh_voxel_indices::Buffer
    mesh_voxels::Mesh
    voxel_transform::fmat4

    cam::Cam3D
    cam_settings::Cam3D_Settings
    inputs::SceneInputs
end
function Base.close(s::Scene)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple(:voxel_transform, :cam, :cam_settings, :inputs)
    whitelist = setdiff(fieldnames(typeof(s)), blacklist)
    for field in whitelist
        close(getfield(s, field))
    end
end

function Scene(window::GLFW.Window, assets::Assets)
    # Generate some voxel data.
    voxel_size = v3i(Val(64))
    voxels = VoxelGrid(undef, voxel_size.data)
    function voxel_func(pos::v3i)::Bool
        posf = (v3f(pos) + @f32(0.5)) / v3f(voxel_size - 1)
        @bpworld_assert posf isa v3f # Double-check the types work as expected
        return vdist(posf, v3f(0.5, 0.5, 0.5)) <= 0.25 # A sphere of radius 0.25
    end
    @threads for i in 1:length(voxels)
        pos = v3i(mod1(i, voxel_size.x),
                  mod1(i ÷ voxel_size.x, voxel_size.y),
                  i ÷ (voxel_size.x * voxel_size.y))
        @inbounds voxels[i] = voxel_func(pos)
    end

    # Set up the mesh for that voxel.
    (voxel_verts, voxel_inds) = calculate_mesh(voxels)
    mesh_voxel_vertices = Buffer(false, voxel_verts)
    mesh_voxel_indices = Buffer(false, voxel_inds)
    mesh_voxels = Mesh(PrimitiveTypes.triangle,
                       [ VertexDataSource(mesh_voxel_vertices, sizeof(voxels[1])) ],
                       voxel_vertex_layout(1),
                       (mesh_voxel_indices, typeof(voxel_inds[1])))
    voxel_transform = m4_world(zero(v3f), fquat(), v3f(Val(1000)))

    window_size::v2i = get_window_size()
    return Scene(
        mesh_voxel_vertices, mesh_voxel_indices, mesh_voxels, voxel_transform,
        Cam3D{Float32}(
            v3f(-100, 500, -100),
            vnorm(v3f(1, 1, 0.3)),
            get_up_vector(),
            Box_minmax(@f32(0.05), @f32(10000)),
            @f32(100),
            @f32(window_size.x / window_size.y)
        ),
        Cam3D_Settings{Float32}(
            move_speed = @f32(200),
            move_speed_min = @f32(1),
            move_speed_max = @f32(1000)
        ),
        SceneInputs(window)
    )
end



"Updates the scene."
function update(scene::Scene, delta_seconds::Float32, window::GLFW.Window)
    # Update inputs.
    for input_names in fieldnames(typeof(scene.inputs))
        field_val = getfield(scene.inputs, input_names)
        if field_val isa AbstractButton
            Bplus.Input.button_update(field_val, window)
        elseif field_val isa AbstractAxis
            Bplus.Input.axis_update(field_val, window)
        else
            error("Unhandled case: ", typeof(field_val))
        end
    end

    # Update the camera.
    # cam_input = Cam3D_Input(
    #     true,

    # )
end

"Renders the scene."
function render(scene::Scene, assets::Assets)
    context::Context = get_context()

    target_activate(nothing)
    set_viewport(zero(v2i), get_window_size())
    set_scissor(nothing)
    set_culling(context, FaceCullModes.Off)
    set_depth_writes(context, true)
    set_depth_test(context, ValueTests.LessThan)
    set_blending(context, make_blend_opaque(BlendStateRGBA))

    render_clear(context, Bplus.GL.Ptr_Target(),
                 vRGBAf(1, 0, 1, 0))
    render_clear(context, Bplus.GL.Ptr_Target(),
                 @f32 1.0)
end