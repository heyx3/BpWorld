cd(joinpath(@__DIR__, ".."))

using Pkg
Pkg.activate(".")

using BpWorld
# All asserts should be disabled by default.
BpWorld.main()