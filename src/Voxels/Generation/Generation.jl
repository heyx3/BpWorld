module Generation

using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.Helpers, Bplus.SceneTree, Bplus.Input
using ..Voxels, ...Utils

"
Some technique for placing voxels in a world.

Should not be used on more than one grid at a time (to allow for caching and memory re-use).
"
abstract type AbstractVoxelGenerator end

#TODO: System to compile AbstractVoxelGenerators into a shader

"
Pre-computes some data that can be used when placing a group of voxels.
This part does not have to be thread-safe.
"
prepare_generation(g::AbstractVoxelGenerator, grid_size::v3u) = nothing

"
Computes the voxel at the given part of the voxel grid.
Must be thread-safe.
" # Types removed from the signature to prevent overload ambiguity
@inline generate(abstract_generator, voxel_idx_v3u, pos_v3f, prepared_data)::UInt8 = (
    if isnothing(prepared_data)
        generate(abstract_generator, voxel_idx_v3u, pos_v3f)
    else
        error("generate() not implemented for ", typeof(abstract_generator),
            " with data ", typeof(prepared_data))
    end
)
generate(abstract_generator, voxel_idx_v3u, pos_v3f) = error(
    "generate() not implemented for ", typeof(abstract_generator)
)


include("field.jl")
include("shapes.jl")
#TODO: Geometric (e.x. generate noise along line)
include("meta.jl")


"Fills a voxel grid using the given generator, optionally keeping within a certain boundary"
function generate!(grid::VoxelGrid, generator::T,
                   bounds::Box3Du = Box_minsize(convert(v3u, one(v3u)),
                                                convert(v3u, vsize(grid)))
                  ) where {T<:AbstractVoxelGenerator}
    prep_data = prepare_generation(generator, convert(v3u, vsize(grid)))
    texel::v3f = @f32(1) / vsize(grid)

    # Put each Z slice in its own task.
    #=Threads.@threads =#for z in bounds.min.z:max_inclusive(bounds).z
        for xy in bounds.min.xy:max_inclusive(bounds).xy
            i = v3u(xy, z)
            p = (i + @f32(0.5)) * texel
            grid[i] = generate(generator, i, p, prep_data)
        end
    end

    return nothing
end


export AbstractVoxelGenerator, prepare_generation, generate,
           VoxelUnion, VoxelDifference, VoxelIntersection,
           VoxelBox, VoxelSphere,
       AbstactNoiseVoxelGenerator, generate_noise,
           Perlin, RidgedPerlin, BillowedPerlin, CustomNoise

end # module