"Manages the main interface for the program"
Base.@kwdef mutable struct GUI
    wnd::GLFW.Window
    service::Service_GUI

    is_debug_window_open::Bool = false

    sun_dir_fallback_yaw::Ref{Float32} = Ref(zero(Float32))
    sun_color_state::Bool = false

    nice_font::Ptr{CImGui.LibCImGui.ImFont} = Ptr{CimGui.LibCImGui.ImFont}(C_NULL)

    #TODO: Give the GuiState types to this struct
end


function Base.close(gui::GUI)
    # No need to close the GUI service manually.
end


function GUI(context::GL.Context, assets::Assets, world::World, view::PostProcess,
             nice_font)
    return GUI(wnd=context.window,
               service=service_GUI(),
               nice_font=nice_font)
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
    gui_with_font(gui.nice_font) do
        gui_window("Main") do
            gui_within_fold("Sun") do
                gui_sun(world.sun, world.sun_gui)
            end
            gui_within_fold("Fog") do
                gui_fog(world.fog, world.fog_gui)
            end
            gui_within_fold("Scene") do
                gui_scene(new_scene_str -> start_new_scene(world, new_scene_str),
                        world.scene, world.scene_gui)
            end
        end
    end
end