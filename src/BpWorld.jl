module BpWorld

using Setfield, Base.Threads, StructTypes, JSON3
using GLFW, ModernGL, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations

using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input

include("Utils/Utils.jl")
using .Utils

include("Voxels/Voxels.jl")
using .Voxels

include("assets.jl")
include("scene.jl")
include("post_process.jl")


function main()
    bp_gl_context(v2i(1500, 900), "B+ World",
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
        scene::Scene = Scene(window, assets)
        view::PostProcess = PostProcess(window, assets, scene)

        last_time_ns = time_ns()
        delta_seconds::Float32 = zero(Float32)
        is_quit_confirming::Bool = false

        GLFW.SetWindowSizeCallback(window, (wnd, new_x, new_y) -> begin
            on_window_resized(scene, wnd, v2i(new_x, new_y))
        end)

        while !GLFW.WindowShouldClose(window)
            check_gl_logs("Top of loop")
            window_size::v2i = get_window_size(context)

            # Update/render the scene.
            update(scene, delta_seconds, window)
            render(scene, assets)
            render(view, window, assets, scene)

            # Handle user input.
            if button_value(scene.inputs.reload_shaders)
                reload_shaders(assets)
            end
            if is_quit_confirming
                draw_scale = v3f(assets.tex_quit_confirmation.size.xy / get_window_size(),
                                 1)
                resource_blit(bp_resources, assets.tex_quit_confirmation,
                              quad_transform=m_scale(draw_scale))
                if button_value(scene.inputs.quit_confirm)
                    break
                elseif button_value(scene.inputs.quit)
                    is_quit_confirming = false
                end
            elseif button_value(scene.inputs.quit)
                is_quit_confirming = true
            end

            # Finish the frame.
            GLFW.SwapBuffers(window)
            GLFW.PollEvents()

            # Update timing.
            now_time_ns = time_ns()
            delta_seconds = (now_time_ns - last_time_ns) / Float32(1e9)
            last_time_ns = now_time_ns
            # Wait, for a consistent framerate that doesn't burn cycles.
            wait_time = (1/60) - delta_seconds
            if wait_time >= 0.001
                sleep(wait_time)
            end
        end

        close(view)
        close(scene)
        close(assets)
    end
end


end # module
