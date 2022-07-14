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
#   Scene Inputs   #
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


#############
#   Scene   #
#############

mutable struct Scene
    voxel_grid::VoxelGrid
    voxel_layers::Vector{Voxels.AssetRenderer}

    mesh_voxel_layers::Vector{Mesh}
    mesh_voxel_buffers::Vector{Buffer}

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
end
function Base.close(s::Scene)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple(:voxel_grid, :total_seconds,
                      :cam, :cam_settings, :is_mouse_captured, :inputs)
    whitelist = setdiff(fieldnames(typeof(s)), blacklist)
    for field in whitelist
        v = getfield(s, field)
        if v isa AbstractVector
            for el in v
                close(el)
            end
            empty!(v)
        else
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

function Scene(window::GLFW.Window, assets::Assets)
    window_size::v2i = get_window_size(window)

    # Hard-code the voxel assets to load for now.
    voxel_assets = [
        Voxels.AssetRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "rocks", "rocks.json"),
                                             "r"),
                                        Voxels.AssetData)),
        Voxels.AssetRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "scifi", "scifi-blue.json"),
                                             "r"),
                                        Voxels.AssetData)),
        Voxels.AssetRenderer(JSON3.read(open(io -> read(io, String),
                                             joinpath(VOXELS_ASSETS_PATH, "scifi", "scifi-red.json"),
                                             "r"),
                                        Voxels.AssetData))
    ]

    # Generate some voxel data.
    voxel_size = v3i(Val(64))
    voxels = VoxelGrid(undef, voxel_size.data)
    voxel_terrain = Voxels.Generation.VoxelField(
        layer = 0x1,
        threshold = @f32(0.3),
        pos_scale = v3f(2, 2, 1),
        field = Voxels.Generation.MathField(*,
            Voxels.Generation.ConstField(0.5),
            Voxels.Generation.MathField(+,
                Voxels.Generation.OctaveNoise(
                    Voxels.Generation.RidgedPerlin(),
                    3
                ),
                Voxels.Generation.BillowedPerlin(5*one(v3f))
            )
        )
    )
    voxel_shape1 = Voxels.Generation.VoxelBox(
        0x2,
        Box_minmax(v3f(Val(0.065)),
                   v3f(Val(0.435))),
        mode = Voxels.Generation.BoxModes.edges
    )
    voxel_shape2 = Voxels.Generation.VoxelSphere(
        center = v3f(0.25, 0.25, 0.75),
        radius = 0.3,
        layer = 0x3
    )
    voxel_scene = Voxels.Generation.VoxelUnion(
        Float32.([ 1.0, 2.0, 3.0 ]),
        Voxels.Generation.VoxelDifference(
            voxel_terrain,
            Voxels.Generation.VoxelBox(
                voxel_shape1.layer,
                Box_minmax(
                    voxel_shape1.area.min / @f32(1.3),
                    max_inclusive(voxel_shape1.area) * @f32(1.3)
                )
            ),
            @set(voxel_shape2.radius *= 1.3)
        ),
        voxel_shape1,
        voxel_shape2
    )
    Voxels.Generation.generate!(voxels, voxel_scene)

    # Set up the meshes for each voxel layer.
    n_layers::Int = max(maximum(voxels), 1)
    voxel_mesh_buffers = Buffer[ ]
    voxel_meshes = Mesh[ ]
    for i in 1:n_layers
        (voxel_verts, voxel_inds) = calculate_mesh(voxels, UInt8(i))

        mesh_voxel_vertices = Buffer(false, voxel_verts)
        mesh_voxel_indices = Buffer(false, voxel_inds)
        push!(voxel_mesh_buffers, mesh_voxel_vertices, mesh_voxel_indices)

        mesh_voxels = Mesh(
            PrimitiveTypes.triangle,
            [ VertexDataSource(mesh_voxel_vertices, sizeof(VoxelVertex)) ],
            voxel_vertex_layout(1),
            (mesh_voxel_indices, eltype(voxel_inds))
        )
        push!(voxel_meshes, mesh_voxels)
    end

    g_buffer_data = set_up_g_buffer(window_size)

    check_gl_logs("After scene initialization")
    return Scene(
        voxels, voxel_assets,
        voxel_meshes, voxel_mesh_buffers,

        Cam3D{Float32}(
            v3f(30, -30, 700),
            vnorm(v3f(1.0, 1.0, -0.8)),
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

        g_buffer_data...
    )
end


#############
#   Logic   #
#############


"Updates the scene."
function update(scene::Scene, delta_seconds::Float32, window::GLFW.Window)
    scene.total_seconds += delta_seconds

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
    if button_value(scene.inputs.capture_mouse)
        scene.is_mouse_captured = !scene.is_mouse_captured
        GLFW.SetInputMode(
            window, GLFW.CURSOR,
            scene.is_mouse_captured ? GLFW.CURSOR_DISABLED : GLFW.CURSOR_NORMAL
        )
    end

    # Update the camera.
    cam_input = Cam3D_Input(
        scene.is_mouse_captured,
        axis_value(scene.inputs.cam_yaw),
        axis_value(scene.inputs.cam_pitch),
        button_value(scene.inputs.cam_sprint),
        axis_value(scene.inputs.cam_forward),
        axis_value(scene.inputs.cam_rightward),
        axis_value(scene.inputs.cam_upward),
        axis_value(scene.inputs.cam_speed_change)
    )
    (scene.cam, scene.cam_settings) = cam_update(scene.cam, scene.cam_settings, cam_input, delta_seconds)
end

"Renders the scene."
function render(scene::Scene, assets::Assets)
    context::Context = get_context()

    set_depth_writes(context, true)

    target_activate(scene.g_buffer)
    for i in 1:3
        target_clear(scene.g_buffer, vRGBAf(0, 0, 0, 0), i)
    end
    target_clear(scene.g_buffer, @f32 1.0)

    # Draw the voxels.
    for (i::Int, mesh::Mesh) in enumerate(scene.mesh_voxel_layers)
        render_voxels(mesh, scene.voxel_layers[i],
                      zero(v3f), v3f(Val(10)),
                      scene.cam, scene.total_seconds)
    end
end

function on_window_resized(scene::Scene, window::GLFW.Window, new_size::v2i)
    if new_size != scene.g_buffer.size
        close.((scene.g_buffer, scene.target_tex_depth,
                scene.target_tex_color, scene.target_tex_normals,
                scene.target_tex_surface))
        new_data = set_up_g_buffer(new_size)
        (
            scene.g_buffer,
            scene.target_tex_depth,
            scene.target_tex_color,
            scene.target_tex_surface,
            scene.target_tex_normals
        ) = new_data
    end
end