# Move to the Julia project folder, and activate this project.
cd(joinpath(@__DIR__, ".."))
using Pkg
Pkg.activate(".")

# The project should be in release mode by default, so just run it!
using BpWorld
@bp_check(!BpWorld.Utils.bpworld_asserts_enabled(), "Debug mode got enabled by default somehow!")
BpWorld.main()