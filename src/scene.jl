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

"Re-usable allocations."
struct SceneCollectionBuffers
    sorted_voxel_layers::Vector{Tuple{Voxels.LayerRenderer, Mesh}}

    SceneCollectionBuffers() = new(
        Vector{Tuple{Voxels.LayerRenderer, Mesh}}()
    )
end

mutable struct Scene
    voxel_grid::VoxelGrid
    voxel_layers::Vector{Voxels.LayerRenderer}
    voxel_scale::Float32

    mesh_voxel_layers::Vector{Mesh}
    mesh_voxel_buffers::Vector{Buffer}

    sun_dir::v3f
    sun_light::vRGBf
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
function Base.close(s::Scene)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple(:voxel_grid, :voxel_scale, :total_seconds,
                      :sun_dir, :sun_light, :sun_viewproj,
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

function Scene(window::GLFW.Window, assets::Assets)
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
    sun_shadowmap_data = set_up_sun_shadowmap(v2i(1024, 1024))

    check_gl_logs("After scene initialization")
    return Scene(
        voxels, voxel_assets, @f32(10),
        voxel_meshes, voxel_mesh_buffers,

        vnorm(v3f(1, 1, -1)),
        one(v3f) * 1,
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


"Renders a depth-only pass using the given view/projection matrices."
function render_depth_only(scene::Scene, assets::Assets, mat_viewproj::fmat4)
    set_color_writes(Vec(false, false, false, false))

    # Sort the voxel layers by their depth-only shader,
    #    to minimize the amount of state changes.
    voxel_layers = scene.buffers.sorted_voxel_layers
    empty!(voxel_layers)
    append!(voxel_layers, zip(scene.voxel_layers, scene.mesh_voxel_layers))
    sort!(voxel_layers, by=(data->GL.gl_type(get_ogl_handle(data[1].shader_program_depth_only))))
    for (layer, mesh) in voxel_layers
        render_voxels_depth_only(mesh, layer,
                                 zero(v3f), one(v3f) * scene.voxel_scale,
                                 scene.cam, mat_viewproj)
    end

    set_color_writes(Vec(true, true, true, true))
end

"Renders the scene."
function render(scene::Scene, assets::Assets)
    context::Context = get_context()

    # Calculate camera matrices.
    mat_cam_view::fmat4 = cam_view_mat(scene.cam)
    mat_cam_proj::fmat4 = cam_projection_mat(scene.cam)
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
    target_activate(scene.g_buffer)
    for i in 1:3
        target_clear(scene.g_buffer, vRGBAf(0, 0, 0, 0), i)
    end
    target_clear(scene.g_buffer, @f32 1.0)

    # Draw the voxels.
    for (i::Int, mesh::Mesh) in enumerate(scene.mesh_voxel_layers)
        render_voxels(mesh, scene.voxel_layers[i],
                      zero(v3f), one(v3f) * scene.voxel_scale,
                      scene.cam, scene.total_seconds,
                      mat_cam_viewproj)
    end

    # Calculate an orthogonal view-projection matrix for the sun's shadow-map.
    # Reference: https://www.gamedev.net/forums/topic/505893-orthographic-projection-for-shadow-mapping/
#TODO: Bound with the entire scene plus view frustum, to catch shadow casters that are outside the frustum
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
    voxels_world_center = scene.voxel_scale * vsize(scene.voxel_grid) / v3f(Val(2))
    # Make a view matrix for the sun looking at that frustum:
    sun_world_pos = voxels_world_center
    @set! sun_world_pos -= scene.sun_dir * max_exclusive(scene.cam.clip_range)
    mat_sun_view::fmat4 = m4_look_at(sun_world_pos, sun_world_pos + scene.sun_dir,
                                     get_up_vector())
    # Get the bounds of the frustum in the sun's view space:
    frustum_points_sun_view = m_apply_point.(Ref(mat_sun_view), frustum_points_world)
    voxel_points_world = tuple((
        scene.voxel_scale * vsize(scene.voxel_grid) * v3f(t...)
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
    scene.sun_viewproj = m_combine(mat_sun_view, mat_sun_proj)
    mat_sun_world_to_texel = m_combine(
        scene.sun_viewproj,
        m_scale(v4f(0.5, 0.5, 0.5, 1.0)),
        m4_translate(v3f(0.5, 0.5, 0.5))
    )

    # Render the sun's shadow-map.
    target_activate(scene.target_shadowmap)
    target_clear(scene.target_shadowmap, @f32 1.0)
    render_depth_only(scene, assets, scene.sun_viewproj)
    target_activate(nothing)
    glGenerateTextureMipmap(get_ogl_handle(scene.target_tex_shadowmap))
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