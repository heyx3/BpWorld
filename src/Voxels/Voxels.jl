module Voxels
    using Setfield, Base.Threads, Dates
    using StructTypes, JSON3,
          GLFW, ModernGLbp, CImGui,
          ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations
    using Bplus,
          Bplus.Utilities, Bplus.Math, Bplus.GL,
          Bplus.Helpers, Bplus.SceneTree, Bplus.Input
    using ..Utils


    const VoxelElement = UInt8
    const EMPTY_VOXEL = zero(VoxelElement)

    const VoxelGrid = AbstractArray{VoxelElement, 3}
    const ConcreteVoxelGrid = Array{VoxelElement, 3}


    # Early-export the things referenced by submodules.
    export VoxelElement, EMPTY_VOXEL,
           VoxelGrid, ConcreteVoxelGrid

    # Compile submodules.
    include("Generation/Generation.jl")

    # Compile files.
    include("layer.jl")
    include("renderer.jl")
    include("renderer_cache.jl")
    include("meshing.jl")
    include("scene.jl")


    export VoxelGrid, ConcreteVoxelGrid,
           VoxelVertex, unpack_vertex, voxel_vertex_layout,
           VoxelMesher, calculate_mesh,
           LayerMaterial, CachedRenderer, RendererCache,
           check_disk_modifications!, get_material!,
           render_voxels, render_voxels_depth_only
end