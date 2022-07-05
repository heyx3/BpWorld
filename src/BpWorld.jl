module BpWorld

using Setfield, Base.Threads
using GLFW, ModernGL, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input


include("utils.jl")
include("voxel_mesher.jl")

include("assets.jl")
include("scene.jl")
include("post_process.jl")


function main()
    bp_gl_context(v2i(1000, 700), "B+ World",
                  vsync=VsyncModes.On,
                  debug_mode=true,
                  glfw_hints = Dict{Int32, Int32}(
                      Int32(GLFW.DEPTH_BITS) => Int32(GLFW.DONT_CARE),
                      Int32(GLFW.STENCIL_BITS) => Int32(GLFW.DONT_CARE)
                  ),
                  glfw_cursor = Val(:Centered)
                 ) do context::Context
        window::GLFW.Window = context.window

        assets::Assets = Assets()
        scene::Scene = Scene(window, assets)
        view::PostProcess = PostProcess(window, assets, scene)

        bp_resources::CResources = get_resources()

        last_time_ns = time_ns()
        delta_seconds::Float32 = zero(Float32)
        is_quit_confirming::Bool = false

        while !GLFW.WindowShouldClose(window)
            check_gl_logs("Top of loop")
            window_size::v2i = get_window_size(context)

            # Update/render the scene.
            update(scene, delta_seconds, window)
            render(scene, assets)

            #TODO: render post-processing.

            # Handle quitting logic.
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
        end

        close(view)
        close(scene)
        close(assets)
    end
end


end # module
