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
"The path where all scene files should be placed"
const SCENES_PATH = joinpath(@__DIR__, "..", "..", "scenes")

"The extension (no period) for scene files"
const SCENES_EXTENSION = "scene"


"Asserts for this specific project: `@bpworld_assert`, `@bpworld_debug`."
@make_toggleable_asserts bpworld_
@assert bpworld_asserts_enabled() == false

"
Removes a type declaration.
This allows you to make a 'default' implementation that explicitly lists types,
    but doesn't risk ambiguity with more specific overloads.
"
macro omit_type(var_decl)
    @assert(Meta.isexpr(var_decl, :(::)) && isa(var_decl.args[1], Symbol),
            "Expected a typed variable declaration, got: $var_decl")
    return esc(var_decl.args[1])
end

"A generator that injects a value in between each element of another iterator"
@inline intersperse(iter, separator) = Iterators.flatten(Iterators.zip(iter, Iterators.repeated(separator)))


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


export @bpworld_assert, @bpworld_debug,
       @omit_type,
       intersperse,
       check_gl_logs,
       ASSETS_PATH, SCENES_PATH,
       process_shader_contents, pixel_converter, load_tex

end # module