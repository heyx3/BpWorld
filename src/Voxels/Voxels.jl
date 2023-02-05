module Voxels
    using Setfield, Base.Threads, StructTypes, JSON3
    using GLFW, ModernGL, CImGui,
          ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
    using Bplus,
          Bplus.Utilities, Bplus.Math, Bplus.GL,
          Bplus.Helpers, Bplus.SceneTree, Bplus.Input
    using ..Utils


    const VOXELS_ASSETS_PATH = joinpath(ASSETS_PATH, "voxels")

    const VoxelElement = UInt8
    const EMPTY_VOXEL = zero(VoxelElement)

    const VoxelGrid = AbstractArray{VoxelElement, 3}
    const ConcreteVoxelGrid = Array{VoxelElement, 3}


    # Early-export the things referenced by submodules.
    export VOXELS_ASSETS_PATH,
           VoxelElement, EMPTY_VOXEL,
           VoxelGrid, ConcreteVoxelGrid

    # Compile submodules.
    include("Generation/Generation.jl")

    # Compile files.
    include("asset.jl")
    include("meshing.jl")
    include("scene.jl")


    export VOXELS_ASSETS_PATH,
           VoxelGrid, ConcreteVoxelGrid,
           VoxelVertex, unpack_vertex, voxel_vertex_layout,
           VoxelMesher, calculate_mesh,
           render_voxels, render_voxels_depth_only
end