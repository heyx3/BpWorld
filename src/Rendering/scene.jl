mutable struct Scene
    voxels_array::VoxelGrid
    voxels::Texture # 3D texture of R8

    sun::UniformBlock_Sun
    fog::UniformBlock_Fog

    layers::Vector{Layer}

    renderers::Dict{Symbol, AbstractLayerRenderer} # Indexed by the lighting model name that layers use
    viewports::Dict{Viewport, AbstractLayerRendererViewport}

    # Each renderer has some asset data per-layer.
    renderer_layer_assets::Dict{AbstractLayerRenderer, Dict{Int, <:AbstractLayerRendererLayer}}

end
@close_gl_resources(s::Scene,
    s.layers,
    values(s.renderers_by_type),
    Iterators.flatten(values(d) for d in values(s.renderer_layer_assets)),
    unzip(s.viewports)...
)