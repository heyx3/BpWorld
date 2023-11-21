module Rendering

using ..Utils, ..Voxels


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
       reset_scene

end