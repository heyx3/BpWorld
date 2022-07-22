module Utils

using Setfield, Base.Threads,
      Suppressor, StructTypes, JSON3, CSyntax
using GLFW, ModernGL, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input
#


"The path where all assets should be placed"
const ASSETS_PATH = joinpath(@__DIR__, "..", "..", "assets")


"Asserts for this specific project: `@bpworld_assert`, `@bpworld_debug`."
@make_toggleable_asserts bpworld_
@assert bpworld_asserts_enabled() == false


"
Removes the type declaration.
This allows you to make a 'default' implementation that explicitly lists types,
    but still doesn't risk ambiguity with more specific overloads.
"
macro omit_type(var_decl)
    @assert(Meta.isexpr(var_decl, :(::)) && isa(var_decl.args[1], Symbol),
            "Expected a typed variable declaration, got: $var_decl")
    return esc(var_decl.args[1])
end


"Checks and prints any messages/errors from OpenGL. Does nothing in release mode."
function check_gl_logs(context::String)
    @bpworld_debug for log in pull_gl_logs()
        if log.severity in (DebugEventSeverities.high, DebugEventSeverities.medium)
            @error "While $context. $(sprint(show, log))"
        elseif log.severity == DebugEventSeverities.low
            @warn "While $context. $(sprint(show, log))"
        elseif log.severity == DebugEventSeverities.none
            @info "While $context. $(sprint(show, log))"
        else
            error("Unhandled case: ", log.severity)
        end
    end
    return nothing
end

include("shaders.jl")
include("textures.jl")
include("gui_integration.jl")


export @bpworld_assert, @bpworld_debug,
       @omit_type,
       check_gl_logs,
       ASSETS_PATH, process_shader_contents,
       pixel_converter, load_tex,
       service_gui_init, service_gui_get,
          service_gui_start_frame, service_gui_end_frame,
          gui_tex

end