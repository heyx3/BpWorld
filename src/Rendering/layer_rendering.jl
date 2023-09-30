#############################
##   AbstractLayerRender   ##
#############################

abstract type AbstractLayerRenderer end

render_init(r::AbstractLayerRenderer,
            voxel_tex_3D::Texture,
            viewport::Viewport
           ) = error("render_init(::", typeof(r), ") not implemented")
render_tick(r::AbstractLayerRenderer,
            delta_seconds::Float32,
            voxel_tex_3D::Texture,
            viewport::Viewport
           ) = error("render_tick(::", typeof(r), ") not implemented")

"Draws this layer for a depth pre-pass, if applicable"
render_depth_prepass(r::AbstractLayerRenderer,
                     voxel_tex_3D::Texture,
                     viewport::Viewport
                    ) = error("render_depth_prepass(::", typeof(r), ") not implemented")

"The main forward-rendering pass for opaque layers"
render_forward_early(r::AbstractLayerRenderer,
                     voxel_tex_3D::Texture,
                     viewport::Viewport
                    ) = error("render_forward_early(::", typof(r), ") not implemented")
"A secondary forward-rendering pass for transparent layers, called after all opaque layers are done"
render_forward_late(r::AbstractLayerRenderer,
                    voxel_tex_3D::Texture,
                    viewport::Viewport
                   ) = error("render_forward_late(::", typeof(r), ") not implemented")


#TODO: Implement different kinds of layer-renderers. Each one is given a meshing task and has its own preview + non-preview shaders



###############
##   Layer   ##
###############

error("#TODO: Layer must use something like RendererCache")
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