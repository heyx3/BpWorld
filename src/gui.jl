const GuiVec2 = CImGui.LibCImGui.ImVec2
const GuiVec4 = CImGui.LibCImGui.ImVec4
const GuiColor = CImGui.LibCImGui.ImColor

@bp_enum SceneState ready compiling error

"Manages the main interface for the program"
Base.@kwdef mutable struct GUI
    wnd::GLFW.Window
    service::Utils.GuiService

    is_debug_window_open::Bool = false

    sun_dir_fallback_yaw::Ref{Float32} = Ref(zero(Float32))
    sun_color_state::Bool = false

    #TODO: Figure out how to make it resizable
    scene_string_buffer::Vector{UInt8} = vcat(Vector{UInt8}("""
# Add a box. Later we will use the inflated box to mask out some terrain.
box_min = { 0.065 }.xxx
box_max = { 0.435 }.xxx
box = Box(
    layer = 0x2,
    min = box_min,
    max = box_max
)
box_inflated = Box(
    layer = 0x2,
    min = box_min / 1.3,
    max = box_max * 1.3
)

# Add a sphere. Later we will use the inflated sphere to mask out some terrain.
sphere_radius = 0.3
sphere_center = { { 0.25 }.xx, 0.75 }
sphere = Sphere(
    layer = 0x3,
    center = sphere_center,
    radius = sphere_radius
)
sphere_inflated = Sphere(
    layer = 0x3,
    center = sphere_center,
    radius = sphere_radius * 1.3
)

# Generate some Perlin noise "terrain".
terrain = BinaryField(
    layer = 0x1,
    field = 0.2 + (0.5 * perlin(pos * 5.0))
)
# Remove any terrain near the box or sphere.
terrain = Difference(
    terrain,
    [ box_inflated, sphere_inflated ]
)

# Combine the terrain with the box and sphere.
return Union(box, sphere, terrain)
    """), fill(zero(UInt8), 2048))
    scene_string_changed::Bool = true
    last_scene_buffer_update_time::UInt64 = 0
    scene_refresh_wait_interval_seconds::Float64 = 3.0
    scene_parse_error_msg::Optional{String} = nothing
    scene_parse_state::E_SceneState = SceneState.ready
end


function Base.close(gui::GUI)
    # No need to close the GUI service manually.
end


function GUI(context::GL.Context, assets::Assets, world::World, view::PostProcess)
    service::Utils.GuiService = Utils.service_gui_init(context)
    return GUI(wnd=context.window, service=service)
end

"""The "debug region" is for debugging data"""
function gui_begin_debug_region(gui::GUI)
    gui.is_debug_window_open = CImGui.Begin("Debugging")
end
function gui_end_debug_region(gui::GUI)
    CImGui.End()
end

"""The "main region" is for the normal, user-facing UI"""
function gui_main_region(gui::GUI, assets::Assets, world::World, view::PostProcess)
    gui_window("Main") do
        gui_within_tree_node("Sun") do
            gui_sun(world.sun, world.sun_gui)
        end
        gui_within_tree_node("Fog") do
            gui_fog(world.fog, world.fog_gui)
        end
        gui_within_tree_node("Scene") do 
            just_changed::Bool = @c CImGui.InputTextMultiline(
                "Code",
                &gui.scene_string_buffer[0], length(gui.scene_string_buffer),
                (0,650),
                CImGui.ImGuiInputTextFlags_AllowTabInput
            )
            gui.scene_string_changed |= just_changed
            if (gui.scene_parse_state == SceneState.ready) && gui.scene_string_changed
                gui.scene_parse_state = SceneState.compiling
            end

            # After enough time, tell the world to try rendering this new scene.
            if just_changed
                gui.last_scene_buffer_update_time = time_ns()
            elseif gui.scene_string_changed && ((time_ns() - gui.last_scene_buffer_update_time) / 1e9) > gui.scene_refresh_wait_interval_seconds
                last_idx = findfirst(iszero, gui.scene_string_buffer) - 1
                scene_str = String(@view gui.scene_string_buffer[1:last_idx])
                gui.scene_parse_error_msg = start_new_scene(world, scene_str)

                gui.scene_string_changed = false
                gui.scene_parse_state = exists(gui.scene_parse_error_msg) ? SceneState.error : SceneState.ready
            end

            CImGui.Spacing()

            # Draw the state of the scene compiler.
            (color, text) = if gui.scene_parse_state == SceneState.ready
                                (GuiVec4(0, 1, 0, 1), "Compiled")
                            elseif gui.scene_parse_state == SceneState.compiling
                                (GuiVec4(1, 1, 0, 1), "Compiling...")
                            elseif gui.scene_parse_state == SceneState.error
                                (GuiVec4(1, 0, 0, 1), gui.scene_parse_error_msg)
                            else
                                error(gui.scene_parse_state)
                            end
            CImGui.TextColored(color, text)
        end
    end
end