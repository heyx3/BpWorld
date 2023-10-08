mutable struct Scene
    voxels_array::VoxelGrid
    voxels::Texture # 3D texture of R8

    sun::UniformBlock_Sun
    fog::UniformBlock_Fog

    layers::Vector{Layer}
    viewports::Set{Viewport}
    renderers::Set{AbstractLayerRender}

    renderers_by_model::Dict{Symbol, AbstractLayerRender}

    # Each renderer has some asset data per-layer and per-viewport.
    renderer_layer_assets::Dict{AbstractLayerRenderer, Dict{Int, <:AbstractLayerRendererLayer}}
    renderer_viewport_assets::Dict{AbstractLayerRenderer, Dict{Viewport, <:AbstractLayerRendererViewport}}

end
@close_gl_resources(s::Scene,
    s.layers, s.viewports, s.renderers,
    (values(data) for data in lookup for lookup in (s.renderer_layer_assets, s.renderer_viewport_assets))...,
    Iterators.flatten(values(d) for d in values(s.renderer_layer_assets)),
    Iterators.flatten(values(d) for d in values(s.renderer_viewport_assets)),
)

"Initializes a new viewport into the scene and returns it. Destroy it with `remove_viewport()`."
function add_viewport( scene::Scene,
                       cam::Cam3D{Float32},
                       settings::Cam3D_Settings{Float32} = Cam3D_Settings{Float32}()
                       ;
                       resolution::v2i = Bplus.GL.get_window_size()
                     )::Viewport
    @set! cam.aspect_width_over_height = resolution.x / @f32(resolution.y)
    viewport = Viewport(
        cam, settings,
        ViewportTarget(resolution), ViewportTarget(resolution)
    )

    #TODO: Register with all renderers

    push!(scene.viewports, viewport)
    return viewport
end
"Cleans up a viewport and removes it from the scene"
function remove_viewport(scene::Scene, viewport::Viewport)

end


function render_scene(s::Scene)

end