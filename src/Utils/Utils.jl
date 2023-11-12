module Utils

using Setfield, Base.Threads,
      Suppressor, StructTypes, JSON3, CSyntax
using GLFW, ModernGLbp, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations,
      MacroTools
using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input
#

# Allows the creation of multiple callbacks to run on program start, via the global list 'RUN_ON_INIT'
@decentralized_module_init

# Defines @bpworld_assert and @bpworld_debug.
# Recompile this project for debug mode by executing `BpWorld.Utils.bpworld_asserts_enabled() = true` at global scope.
@make_toggleable_asserts bpworld_


# File paths need to be configured at runtime.
# Otherwise deployed builds will try to use developers' file paths!
"The root path of this project"
ROOT_PATH::String = ""
"The path where all scene files should be placed"
SCENES_PATH::String = ""
"The path where all voxel layers should be placed"
VOXEL_LAYERS_PATH::String = ""
"The path where internal assets should be placed"
ASSETS_PATH::String = ""

push!(RUN_ON_INIT, () -> begin
    path_base = pwd()

    global ROOT_PATH
    # In standalone builds, back out of the 'bin' folder.
    if isfile(joinpath(path_base, "BpWorld.exe"))
        ROOT_PATH = joinpath(path_base, "..")
    # In the repo, sit in the project folder.
    elseif isfile(joinpath(path_base, "src/BpWorld.jl"))
        ROOT_PATH = path_base
    else
        error("Can't find 'src/BpWorld.jl', so we're not in a Julia project. ",
                "Can't find 'BpWorld.exe', so we're not in a deployed build. ",
                "We aren't in a valid location!")
    end
    ROOT_PATH = normpath(ROOT_PATH)
    println(stderr, "Using root path {", ROOT_PATH, "}")

    # Ideally in deployment we'd respect OS conventions
    #    about where to put temp files vs save files vs installed files,
    #    but I don't even know if that information is gettable through Julia.
    # So just keep everything together in the build folder.
    global SCENES_PATH = joinpath(ROOT_PATH, "scenes")
    global VOXEL_LAYERS_PATH = joinpath(ROOT_PATH, "layers")
    global ASSETS_PATH = joinpath(ROOT_PATH, "assets")
end)


"The extension (no period) for scene files"
const SCENES_EXTENSION = "scene"

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


"
Simplifies a common design pattern for data containing B+ GL resources.
Defines `Base.close()` for a type to iterate through its fields, and calling `close()` on any resources.

You may also provide extra iterables of objects to call `close()` on.

Example:

````
@close_gl_resources(x::MyAssets, values(x.texture_lookup), x.my_file_handles)
````
"
macro close_gl_resources(object, iterators...)
    if !@capture(object, name_Symbol::type_)
        error("Expected first argument to be in the form 'name::Type'. Got: ", object)
    end
    object = esc(object)
    name = esc(name)
    type = esc(type)
    iterators = esc.(iterators)
    return :(
        function Base.close($object)
            resources = Iterators.flatten(tuple(
                Iterators.filter(field -> field isa $(Bplus.GL.AbstractResource),
                                 getfield.(Ref($name), fieldnames($type))),
                $(iterators...)
            ))
            for r in resources
                close(r)
            end
        end
    )
end


export @bpworld_assert, @bpworld_debug,
       @omit_type, @close_gl_resources,
       check_gl_logs,
       ROOT_PATH,
       VOXEL_LAYERS_PATH, ASSETS_PATH, SCENES_PATH,
       SCENES_EXTENSION,
       process_shader_contents, pixel_converter, load_tex

end # module