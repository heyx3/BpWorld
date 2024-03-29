module BpWorld

using Setfield, Base.Threads, StructTypes, JSON3

using GLFW, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations,
      CSyntax

# Just to keep PackageCompiler happy.
# I don't really understand why it was needed though.
using PNGFiles, ImageMagick

using Bplus; @using_bplus
const ModernGLbp = Bplus.GL.ModernGLbp


include("Utils/Utils.jl")
using .Utils

include("Voxels/Voxels.jl")
using .Voxels

include("gui_data.jl")
include("assets.jl")
include("world.jl")
include("post_process.jl")
include("gui.jl")

function main()::Nothing
    @game_loop begin
        INIT(
            v2i(1600, 900), "B+ World",
            vsync=VsyncModes.on,
            debug_mode=@bpworld_debug(),
            glfw_hints = Dict{Int32, Int32}(
                Int32(GLFW.DEPTH_BITS) => Int32(GLFW.DONT_CARE),
                Int32(GLFW.STENCIL_BITS) => Int32(GLFW.DONT_CARE)
            )
        )

        SETUP = begin
            gui_nice_font_config = CImGui.ImFontConfig_ImFontConfig()
            unsafe_store!(gui_nice_font_config.OversampleH, Cint(8))
            unsafe_store!(gui_nice_font_config.OversampleV, Cint(8))
            gui_nice_font = CImGui.AddFontFromFileTTF(unsafe_load(CImGui.GetIO().Fonts),
                                                      joinpath(ASSETS_PATH, "fonts/RonysiswadiArchitect4-qZmp2/font.ttf"),
                                                      16,
                                                      gui_nice_font_config)
            CImGui.ImFontConfig_destroy(gui_nice_font_config)

            assets::Assets = Assets()
            world::World = World(LOOP.context.window, assets)
            view::PostProcess = PostProcess(LOOP.context.window, assets, world)
            gui::GUI = GUI(LOOP.context, assets, world, view, gui_nice_font)

            is_quit_confirming::Bool = false

            push!(LOOP.context.glfw_callbacks_window_resized, new_size::v2i -> begin
                on_window_resized(world, LOOP.context.window, new_size)
            end)
        end

        LOOP = begin
            check_gl_logs("Top of loop")
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end
            window_size::v2i = get_window_size(LOOP.context)

            gui_begin_debug_region(gui)
            update(world, LOOP.delta_seconds, LOOP.context.window)
            update_buffers(assets, world.fog, world.sun, world.cam, world.target_tex_shadowmap,
                # The light's view-projection matrix brings it into NDC space, -1 to +1.
                # We need to take it one step further, into "texel" space, 0 to 1.
                # This includes the Z value, since the depth texture normalizes depth to that range.
                m_combine(
                    world.sun_viewproj,
                    m_scale(v4f(0.5, 0.5, 0.5, 1.0)),
                    m4_translate(v3f(0.5, 0.5, 0.5))
                )
            )
            render(world, assets)
            render(view, LOOP.context.window, assets, world)
            gui_end_debug_region(gui)
            gui_main_region(gui, assets, world, view)

            # Handle user input.
            if input_reload_shaders()
                reload_shaders(assets)
            end
            if is_quit_confirming
                draw_scale = v3f((assets.tex_quit_confirmation.size.xy / window_size)...,
                                 1)
                simple_blit(assets.tex_quit_confirmation,
                            quad_transform=m_scale(draw_scale))
                if input_quit_confirm()
                    break
                elseif input_quit()
                    is_quit_confirming = false
                end
            elseif !CImGui.IsAnyItemFocused() && input_quit()
                is_quit_confirming = true
            end

            # Force-show the window after precompilation is done.
            if LOOP.frame_idx == 10
                GLFW.ShowWindow(LOOP.context.window)
            end
        end

        TEARDOWN = begin
            close(view)
            close(world)
            close(assets)
        end
    end
end

function julia_main()::Cint
    try
        main()
        return 0
    catch e
        @error "$(sprint(showerror, e, catch_backtrace()))"
        return 1
    end # try
end # julia_main

end # module
