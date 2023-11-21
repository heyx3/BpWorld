"The extension (no period) for scene files"
const SCENES_EXTENSION = "scene"


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