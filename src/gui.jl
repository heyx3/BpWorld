"Manages the main interface for the program"
Base.@kwdef mutable struct GUI
    wnd::GLFW.Window
    service::Utils.GuiService

    is_debug_window_open::Bool = false
end

function Base.close(gui::GUI)
    # No need to close the GUI service manually.
end


function GUI(context::GL.Context, assets::Assets, scene::Scene, view::PostProcess)
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
function gui_main_region(gui::GUI, assets::Assets, scene::Scene, view::PostProcess)
    CImGui.Begin("Main")

    CImGui.End()
end