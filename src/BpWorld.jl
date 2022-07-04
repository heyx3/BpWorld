module BpWorld

using GLFW, ModernGL, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers
using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input


include("utils.jl")
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
        scene::Scene = Scene(assets)
        view::PostProcess = PostProcess()

        last_time_ns = time_ns()
        delta_seconds::Float32 = zero(Float32)

        while !GLFW.WindowShouldClose(window)
            check_gl_logs("Top of loop")
            window_size::v2i = get_window_size(context)

            #TODO: Stuff.

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
