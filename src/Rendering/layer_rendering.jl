###############################
##   AbstractLayerRenderer   ##
###############################

##  Types  ##

"
The current state of a lighting model as represented by some type of `AbstractLayerDataLightingModel`.
Only one exists for each type of lighting model, and it is responsible
    for rendering *all* layers using that model.
This architecture allows for funky techniques like OIT.

For data associated with a specific layer, define a custom `AbstractLayerDataLayer`.

If your renderer has data associated with a specific Viewport,
    define a custom `AbstractLayerRendererViewport`.
"
abstract type AbstractLayerRenderer end
@close_gl_resources(r::AbstractLayerRenderer)

"
Any assets of an `AbstractLayerRenderer` that are associated with a specific view,
    such as intermediary render targets, can go here
"
abstract type AbstractLayerRendererViewport end
@close_gl_resources(v::AbstractLayerRendererViewport)

"
Any assets of an `AbstractLayerRenderer` that are associated with a specific layer,
    such as its shaders, can go here
"
abstract type AbstractLayerRendererLayer end
@close_gl_resources(l::AbstractLayerRendererLayer)


##  Lifetime management  ##

"Creates a layer renderer for instances of the given kind of lighting model"
function layer_renderer_init(T::Type{<:AbstractLayerDataLightingModel},
                             scene,
                            )::AbstractLayerRenderer
    error("layer_renderer_init() not defined for ", T)
end

"Creates a layer renderer's assets for a specific viewport"
function layer_renderer_init_viewport(r::AbstractLayerRenderer,
                                      viewport::Viewport,
                                      scene
                                     )::AbstractLayerRendererViewport
    error("layer_renderer_init_viewport() not defined for ", typeof(r))
end
"Called just before calling `close()` on a viewport's specific assets"
function layer_renderer_close_viewport(r::AbstractLayerRenderer,
                                       v::Viewport,
                                       rv::AbstractLayerRendererViewport,
                                       scene)
    error("layer_renderer_close_viewport(::", typeof(r), ") not implemented")
end

"Creates a layer renderer's assets for a specific layer"
function layer_renderer_init_layer(r::AbstractLayerRenderer,
                                   layer_data::LayerDefinition,
                                   scene
                                  )::AbstractLayerRendererLayer
    error("layer_renderer_init_layer() not defined for ", typeof(r))
end
"Called just before calling `close()` on a layer's specific assets"
function layer_renderer_close_layer(r::AbstractLayerRenderer,
                                    v::Viewport,
                                    rv::AbstractLayerRendererViewport,
                                    scene)
    error("layer_renderer_close_layer(::", typeof(r), ") not implemented")
end

#TODO: Layer renderer should handle the output of the meshing algorithm.

function layer_renderer_tick(r::AbstractLayerRenderer,
                             viewports::Dict{Viewport, <:AbstractLayerRendererViewport},
                             layers::Dict{Int, <:AbstractLayerRendererLayer},
                             scene,
                             delta_seconds::Float32)
    error("layer_renderer_tick(::", typeof(r), ") not implemented")
end


##  Render passes  ##

@bp_enum(Pass,
    depth, shadow_map,
    forward
)
struct PassInfo
    type::E_Pass
    # Future data may go here.
end


"Higher numbers are rendered earlier"
layer_renderer_order(r::AbstractLayerRenderer, pass_info::PassInfo)::Int = error("layer_renderer_order(::", typeof(r), ") not implemented")
"Whether a renderer needs to sample from one of the previous passes' textures, for things like refraction"
layer_renderer_reads_target(r::AbstractLayerRenderer, pass_info::PassInfo)::Bool = error("layer_renderer_reads_target(::", typeof(r), ") not implemented")

"Executes a renderer on the given layers, for the given pass"
function layer_renderer_execute(r::AbstractLayerRenderer,
                                viewport::Viewport,
                                view_state::AbstractLayerRendererViewport,
                                layers::Dict{Int, <:AbstractLayerRendererLayer},
                                scene,
                                pass_info::PassInfo,
                                applicable_layers::Vector{Int})
    error("layer_renderer_execute(::", typeof(r), ", ...) not implemented")
end