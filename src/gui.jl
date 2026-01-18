"Manages the main interface for the program"
Base.@kwdef mutable struct GUI
    wnd::GLFW.Window
    service::Service_GUI

    is_debug_window_open::Bool = false # Always false in Release builds

    sun_dir_fallback_yaw::Ref{Float32} = Ref(zero(Float32))
    sun_color_state::Bool = false

    nice_font::Ptr{CImGui.LibCImGui.ImFont} = Ptr{CimGui.LibCImGui.ImFont}(C_NULL)

    #TODO: Give the GuiState types to this struct
end


function Base.close(gui::GUI)
    # No need to close the GUI service manually.
end


function GUI(context::GL.Context, assets::Assets, world::World,
             nice_font)
    return GUI(wnd=context.window,
               service=service_GUI(),
               nice_font=nice_font)
end

"Call before world logic"
function gui_begin_debug_region(gui::GUI)
    @bpworld_debug begin
        gui.is_debug_window_open = CImGui.Begin("Debugging")
    end
end
"Call just after world logic, and before the usual GUI logic"
function gui_end_debug_region(assets::Assets, world::World, gui::GUI)
    @bpworld_debug begin
        # Add a divider after any debug GUI stuff from the world logic.
        CImGui.Separator()

        #TODO: Display textures

        CImGui.End()
    end
end


function gui_main_region(gui::GUI, assets::Assets, world::World)
    gui_with_font(gui.nice_font) do
        CImGui.SetNextWindowPos((5, 5))
        CImGui.SetNextWindowSize((425, 800))
        gui_window("Main", C_NULL, CImGui.LibCImGui.ImGuiWindowFlags_NoDecoration) do
            gui_within_fold("Sun") do
                gui_sun(world.sun, world.sun_gui)
            end
            gui_within_fold("Fog") do
                gui_fog(world.fog, world.fog_gui)
            end
            gui_within_fold("Scene") do
                gui_scene(new_scene_str -> start_new_scene(world.renderer, new_scene_str, v3i(64, 64, 64)),
                          world.scene, world.scene_gui)
            end
        end
    end
end