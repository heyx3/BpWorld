# Point Julia and Pkg to this project.
using Pkg
cd(@__DIR__)
Pkg.activate(".")

# Add our ModernGL fork, ModernGLbp, as a dependency.
using Bplus
const PATH_TO_BP_PROJECT = abspath(joinpath(pathof(Bplus), "..", ".."))
const PATH_TO_MODERNGLBP = joinpath(PATH_TO_BP_PROJECT, "dependencies", "ModernGLbp.jl")
Pkg.develop(url=PATH_TO_MODERNGLBP)

Pkg.instantiate()
Pkg.precompile()