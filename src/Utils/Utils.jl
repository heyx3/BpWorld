module Utils

using Setfield, Base.Threads,
      Suppressor, StructTypes, JSON3, CSyntax
using GLFW, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
using Bplus; @using_bplus
const ModernGLbp = Bplus.GL.ModernGLbp
#

@decentralized_module_init


# Paths need to be set up at runtime.
# A function below will initialize them dynamically.

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
    if isfile(joinpath(path_base, "BpWorld.exe"))
        ROOT_PATH = joinpath(path_base, "..")
    elseif isfile(joinpath(path_base, "src/BpWorld.jl"))
        ROOT_PATH = path_base
    else
        error("Can't find 'src/BpWorld.jl', so we're not in a Julia project. ",
                "Can't find 'BpWorld.exe', so we're not in a deployed build. ",
                "We aren't in a valid location!")
    end
    ROOT_PATH = normpath(ROOT_PATH)

    println(stderr, "Using root path {", ROOT_PATH, "}")
    global SCENES_PATH = joinpath(ROOT_PATH, "scenes")
    global VOXEL_LAYERS_PATH = joinpath(ROOT_PATH, "layers")
    global ASSETS_PATH = joinpath(ROOT_PATH, "assets")
end)


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

include("shaders.jl")
include("textures.jl")


export @bpworld_assert, @bpworld_debug,
       @omit_type,
       intersperse,
       ROOT_PATH,
       VOXEL_LAYERS_PATH, ASSETS_PATH, SCENES_PATH,
       SCENES_EXTENSION,
       process_shader_contents, pixel_converter, load_tex

end # module