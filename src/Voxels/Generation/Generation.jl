module Generation

using Setfield, DataStructures
using MacroTools
using Bplus; @using_bplus
using ..Voxels, ...Utils

"Some technique for placing voxels in a world."
abstract type AbstractVoxelGenerator end

#TODO: System to compile AbstractVoxelGenerators into a shader


"
Runs a voxel generator on a grid.
You can also control whether threading is allowed or not.
"
generate!(grid::VoxelGrid, v::AbstractVoxelGenerator, use_threads::Bool) = error("generate!() not implemented for ", typeof(v))
"
Runs a voxel generator on a grid and returns it.
You can also control whether threading is allowed or not.
"
function generate(grid_size::Vec3{<:Integer},
                  v::AbstractVoxelGenerator,
                  use_threads::Bool)
    grid = ConcreteVoxelGrid(undef, grid_size.data)
    generate!(grid, v, use_threads)
    return grid
end


include("dsl.jl")

include("field.jl")
include("shapes.jl")
include("meta.jl")



export AbstractVoxelGenerator, generate!, generate,
           VoxelBinaryField,
           VoxelBox, VoxelSphere, BoxModes, E_BoxModes,
           VoxelUnion, VoxelDifference, VoxelIntersection,
           DslState, DslError, eval_dsl, dsl_expression

end # module