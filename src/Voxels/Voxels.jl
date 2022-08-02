module Voxels
    using Setfield, Base.Threads, StructTypes, JSON3
    using GLFW, ModernGL, CImGui,
          ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
    using Bplus,
          Bplus.Utilities, Bplus.Math, Bplus.GL,
          Bplus.Helpers, Bplus.SceneTree, Bplus.Input
    using ..Utils


    const VOXELS_ASSETS_PATH = joinpath(ASSETS_PATH, "voxels")

    const VoxelGrid = Array{UInt8, 3}
    const EMPTY_VOXEL = zero(UInt8)

    # Early exports are needed for sub-modules.
    export VOXELS_ASSETS_PATH, VoxelGrid, EMPTY_VOXEL
    include("Generation/Generation.jl")

    include("asset.jl")
    include("meshing.jl")
    include("scene.jl")

    export VOXELS_ASSETS_PATH,
           VoxelGrid,
           VoxelVertex, unpack_vertex, voxel_vertex_layout,
           VoxelMesher, calculate_mesh,
           render_voxels, render_voxels_depth_only
end