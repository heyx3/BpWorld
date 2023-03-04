module BpWorld

using Setfield, Base.Threads, StructTypes, JSON3
using GLFW, ModernGL, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations,
      CSyntax

using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input

include("Utils/Utils.jl")
using .Utils

include("Voxels/Voxels.jl")
using .Voxels

include("gui_data.jl")
include("assets.jl")
include("world.jl")
include("post_process.jl")
include("gui.jl")


function main()
    bp_gl_context(v2i(1600, 900), "B+ World",
                  vsync=VsyncModes.On,
                  debug_mode=@bpworld_debug(),
                  glfw_hints = Dict{Int32, Int32}(
                      Int32(GLFW.DEPTH_BITS) => Int32(GLFW.DONT_CARE),
                      Int32(GLFW.STENCIL_BITS) => Int32(GLFW.DONT_CARE)
                  )
                 ) do context::Context
        window::GLFW.Window = context.window

        bp_resources::CResources = get_resources()
        assets::Assets = Assets()
        world::World = World(window, assets)
        view::PostProcess = PostProcess(window, assets, world)
        gui::GUI = GUI(context, assets, world, view)

        last_time_ns = time_ns()
        delta_seconds::Float32 = zero(Float32)
        is_quit_confirming::Bool = false
        frame_idx::UInt = zero(UInt)

        GLFW.SetWindowSizeCallback(window, (wnd, new_x, new_y) -> begin
            on_window_resized(world, wnd, v2i(new_x, new_y))
        end)

        while !GLFW.WindowShouldClose(window)
            check_gl_logs("Top of loop")
            GLFW.PollEvents()
            window_size::v2i = get_window_size(context)

            # Update/render the world.
            service_gui_start_frame(gui.service)
            gui_begin_debug_region(gui)
            update(world, delta_seconds, window)
            render(world, assets)
            render(view, window, assets, world)
            gui_end_debug_region(gui)
            gui_main_region(gui, assets, world, view)
            service_gui_end_frame(gui.service, context)

            # Handle user input.
            if button_value(world.inputs.reload_shaders)
                reload_shaders(assets)
                reload_shaders(world, assets)
            end
            if is_quit_confirming
                draw_scale = v3f((assets.tex_quit_confirmation.size.xy / get_window_size())...,
                                 1)
                resource_blit(bp_resources, assets.tex_quit_confirmation,
                              quad_transform=m_scale(draw_scale))
                if button_value(world.inputs.quit_confirm)
                    break
                elseif button_value(world.inputs.quit)
                    is_quit_confirming = false
                end
            elseif !CImGui.IsAnyItemFocused() && button_value(world.inputs.quit)
                is_quit_confirming = true
            end

            GLFW.SwapBuffers(window)

            # Update timing.
            now_time_ns = time_ns()
            delta_seconds = (now_time_ns - last_time_ns) / Float32(1e9)
            last_time_ns = now_time_ns
            # Cap the duration of a frame, so big hangs don't cause chaos.
            delta_seconds = min(0.2, delta_seconds)

            # Wait, for a consistent framerate that doesn't burn cycles.
            wait_time = (1/60) - delta_seconds
            if wait_time >= 0.001
                sleep(wait_time)
            end

            # Force-show the window after precompilation is done.
            frame_idx += 1
            if frame_idx <= 10
                GLFW.ShowWindow(window)
            end
        end

        close(view)
        close(world)
        close(assets)
    end
end


end # module
