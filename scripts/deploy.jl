# Creates a built version of the game.
# Pass '--skip-play' or '-s' to use the pre-existing "precompiles.jl" file,
#    instead of playing the game to create a new one.
# Pass '--incremental' or '-i' for an incremental build.

# Configuration:
const APP_NAME = "VoxelToy"
const FOLDERS_TO_COPY = [ "assets", "layers", "scenes" ]
const BUILD_FOLDER = "build"
const TOP_LEVEL_CONTENTS_FOLDER = "CopyToBuild"

# Move to the game project folder.
cd(joinpath(@__DIR__, ".."))

# Run the game to learn the set of functions to precompile.
if !any(arg -> arg in ARGS, [ "-s", "--skip-play" ])
    mkpath(BUILD_FOLDER)
    julia_path = joinpath(Sys.BINDIR, "julia")
    run(`$julia_path --project=. --trace-compile=build/precompiles.jl
        -e 'using BpWorld; BpWorld.julia_main()'`)
end

# Generate a standalone app.
using PackageCompiler
PackageCompiler.create_app(
    ".", "build/$APP_NAME",
    precompile_statements_file="build/precompiles.jl",
    incremental=(("-i" in ARGS) || ("--incremental" in ARGS)),
    force=true,
    include_transitive_dependencies=false
)

# Copy asset folders over.
for folder_name in FOLDERS_TO_COPY
    Base.Filesystem.cp(joinpath(pwd(), folder_name),
                       joinpath(pwd(), BUILD_FOLDER,
                                APP_NAME, folder_name),
                       force=true)
end

# Copy top-level scripts over.
for element in readdir(joinpath(pwd(), BUILD_FOLDER, TOP_LEVEL_CONTENTS_FOLDER))
    Base.Filesystem.cp(joinpath(pwd(), BUILD_FOLDER, TOP_LEVEL_CONTENTS_FOLDER, element),
                       joinpath(pwd(), BUILD_FOLDER, APP_NAME, element),
                       force=true)
end