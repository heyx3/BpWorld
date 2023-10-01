###############################
##   AbstractLayerRenderer   ##
###############################

"
The current state of a lighting model as represented by some type of `AbstractLayerDataLightingModel`.
Only one exists for each type of lighting model, and it is responsible
    for rendering *all* layers using that model, to allow for funky techniques like OIT.

If your renderer has some data that changes based on viewport,
    define a custom `AbstractLayerRendererViewport`.
"
abstract type AbstractLayerRenderer end
@close_gl_resources(r::AbstractLayerRenderer)

"
Any assets of an `AbstractLayerRenderer` that are associated with a specific view,
    such as render targets of a certain resolution, can go here
"
abstract type AbstractLayerRendererViewport end
@close_gl_resources(v::AbstractLayerRendererViewport)


##  Lifetime management  ##

"Creates a layer renderer for instances of the given kind of lighting model"
function layer_renderer_init(T::Type{<:AbstractLayerDataLightingModel},
                             scene,
                            )::AbstractLayerRenderer
    error("layer_renderer_init() not defined for ", T)
end

function layer_renderer_init_viewport(r::AbstractLayerRenderer,
                                      viewport::Viewport,
                                      scene
                                     )::AbstractLayerRendererViewport
    error("layer_renderer_init_viewport() not defined for ", typeof(r))
end

# Default close() behavior simply destroys all fields that are B+ Resources.
function Base.close(r::AbstractLayerRenderer)
    for field in getfield.(Ref(r), fieldnames(typeof(r)))
        if field isa Bplus.GL.AbstractResource
            close(field)
        end
    end
end
function Base.close(rv::AbstractLayerRendererViewport)
    for field in getfield.(Ref(rv), fieldnames(typeof(rv)))
        if field isa Bplus.GL.AbstractResource
            close(field)
        end
    end
end

"
Updates this renderer.

Note that the set of `applicable_layers` can change without warning from frame to frame,
    after the voxel scene is hot-reloaded from file changes,
    so don't assume the collection is static.
"
function layer_renderer_tick(r::AbstractLayerRenderer,
                             viewport_data::Dict{Viewport, <:AbstractLayerRendererViewport}
                             scene,
                             applicable_layers::Vector{Int},
                             delta_seconds::Float32)
    error("layer_renderer_tick(::", typeof(r), ") not implemented")
end


##  Render passes  ##

"Higher numbers are rendered earlier"
layer_renderer_order(r::AbstractLayerRenderer)::Int = error("layer_renderer_order(::", typeof(r), ") not implemented")
"Whether a renderer needs to sample from one of the previous passes' textures, for things like refraction"
layer_renderer_reads_target(r::AbstractLayerRenderer)::Bool = error("layer_renderer_reads_target(::", typeof(r), ") not implemented")

"Executes a renderer's pass"
function layer_renderer_execute(r::AbstractLayerRenderer,
                                viewport::Viewport,
                                view_state::AbstractLayerRendererViewport,
                                scene,
                                applicable_layers::Vector{Int})
    error("layer_renderer_execute(::", typeof(r), ") not implemented")
end


###############
##   Layer   ##
###############

println("#TODO: Layer must use something like RendererCache")
mutable struct Layer
    renderer::AbstractLayerRenderer


    # Mapped by uniform name
    textures::Dict{AbstractString, Texture}
end

function Base.close(l::Layer)
    close(l.renderer)
    close.(values(m.textures))
    empty!(m.textures)
end