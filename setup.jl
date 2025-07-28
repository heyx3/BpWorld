# Point Julia and Pkg to this project.
using Pkg
cd(@__DIR__)
Pkg.activate(".")

Pkg.instantiate()
Pkg.precompile()