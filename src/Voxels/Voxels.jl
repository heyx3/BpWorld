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

    include("asset.jl")
    include("meshing.jl")

    export VOXELS_ASSETS_PATH,
           VoxelGrid,
           VoxelVertex, unpack_vertex, voxel_vertex_layout,
           calculate_mesh, render_voxels
end