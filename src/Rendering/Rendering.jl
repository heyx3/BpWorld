module Rendering

using Setfield, DataStructures
using MacroTools, StructTypes, JSON3

using Bplus; @using_bplus

using ..Utils, ..Generation
using ..BpWorld: VoxelGrid, VoxelElement, EMPTY_VOXEL, AbstractVoxelGrid


include("viewport.jl")
include("world_buffers.jl")

include("layer_meshing.jl")
include("layer_data_definition.jl")
include("layer_rendering.jl")
include("layer_render_shaders.jl")

include("shadowmap.jl")
include("sky.jl")
include("scene.jl")

include("layer_render_models.jl")

export Scene, RenderSettings, begin_scene_frame, end_scene_frame,
       Viewport, add_viewport, remove_viewport, render_viewport,
       start_new_scene, reset_scene,
       UniformBlock_Fog, UniformBlock_Sun, UniformBlock_Viewport

end