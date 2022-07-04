# Based on this reference implementation of a CImGui backend:
#    https://github.com/Gnimuc/CImGui.jl/blob/master/examples/Renderer.jl

mutable struct GUI
    ptr::Ptr{ImGuiContext}
    wnd::GLFW.Window
end

function GUI(window::GLFW.Window)
    ptr = CImGui.CreateContext()
    CImGui.StyleColorsDark()

    #TODO: Finish:
    #    https://github.com/JuliaImGui/ImGuiGLFWBackend.jl/tree/master/src
    #    https://github.com/JuliaImGui/ImGuiOpenGLBackend.jl
end