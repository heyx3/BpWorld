"For layer renderers that have no special per-Viewport assets"
struct LayerRendererViewportBasic <: AbstractLayerRendererViewport end


###################################################
##    Common (CookTorrance, dielectric and metal)

"Data definition of a layer lit with the Common model."
@kwdef struct LightingModel_Common <: AbstractLayerDataLightingModel
    two_sided::Bool = false
end
lighting_model_serialized_name(::Type{LightingModel_Common}) = :common
lighting_model_type(::Val{:common}) = LightingModel_Common


"Renders layers using a standard PBR model"
mutable struct LayerRenderer_Common <: AbstractLayerRenderer
end

"Per-viewport data for the Common renderer"
mutable struct LayerRendererViewport_Common <: AbstractLayerRendererViewport
end
"Per-layer data for the Common renderer"
mutable struct LayerRendererLayer_Common <: AbstractLayerRendererLayer
    # Separate shaders for pre-meshed ("preview") and post-meshed.
    # Supports Forward pass and Depth pass (re-using Depth for shadows pass).
    depth_preview::Program
    depth_meshed::Program
    forward_preview::Program
    forward_meshed::Program
end


const COMMON_MODEL_FRAG_SHADER_HEADER_FORWARD = """
    $(LayerShaders.SHADER_FRAG_HEADER)
    #define PASS_FORWARD 1

    layout (location = 0) out vec3 fOut_color;
    layout (location = 1) out vec3 fOut_emission;

    void finish(vec3 albedo, vec3 emissive,
                float metallic, float roughness,
                vec3 tangentSpaceNormal,
                InData inputs)
    {
        //TODO: Apply tangentSpaceNormal to world normals (add tangent and bitangent to InData).

        vec3 fragToCam = inputs.worldPos - u_cam.pos.xyz;
        float distFragToCam = length(fragToCam);
        vec3 fragToCamN = fragToCam / distFragToCam;

        //Calculate PBR.
        vec3 surfaceColor = microfacetLighting(
            inputs.worldNormal,
            fragToCamN,
            -u_sun.dir.xyz, u_sun.emission.rgb,
            albedo, metallic, roughness
        );

        //Apply shadows and GI.
        surfaceColor = saturate(
            computeAmbient(inputs.worldPos, inputs.worldNormal, albedo) +
            (localLight * computeShadows(inputs.worldPos))
        );

        //TODO: Apply emissive to surface color. How should it interact with fog?

        //Apply fog.
        surfaceColor = computeFoggedColor(
            u_cam.pos.z, inputs.worldPos.z,
            distFragToCam, abs(fragToCam.z),
            surfaceColor
        );

        //Write to the render targets.
        fOut_color = surfaceColor;
        fOut_emission = emissive;
    }
"""

const COMMON_MODEL_FRAG_SHADER_HEADER_DEPTH = """
    $(LayerShaders.SHADER_FRAG_HEADER)
    #define PASS_DEPTH 1

    void finish() { }
"""


##   Lifetime Management   ##

function layer_renderer_init(::Type{LightingModel_Common}, scene::Scene)
    return LayerRenderer_Common()
end

function layer_renderer_init_viewport(r::LayerRenderer_Common, v::Viewport, s::Scene)
    return LayerRendererViewport_Common()
end
function layer_renderer_close_viewport(r::LayerRenderer_Common,
                                       v::Viewport, rv::LayerRendererViewport_Common,
                                       s::Scene)
    close(rv)
    return nothing
end

function layer_renderer_init_layer(r::LayerRenderer_Common,
                                   l::LayerDefinition,
                                   s::Scene)
    #TODO: Set up shaders
end
function layer_renderer_close_layer(r::LayerRenderer_Common,
                                    l::LayerDefinition,
                                    rl::LayerRendererLayer_Common,
                                    s::Scene)
    close(rl)
    return nothing
end

function layer_renderer_tick(r::LayerRenderer_Common,
                             viewports::Dict{Viewport, <:AbstractLayerRendererViewport},
                             layers::Dict{Int, <:AbstractLayerRendererLayer},
                             scene::Scene,
                             delta_seconds::Float32)
    return nothing
end

##   Rendering   ##

layer_renderer_order(::LayerRenderer_Common, ::PassInfo) = 0
layer_renderer_reads_target(::LayerRenderer_Common, ::PassInfo) = false

function layer_renderer_execute(renderer::LayerRenderer_Common,
                                viewport::Viewport,
                                viewport_assets::LayerRendererViewport_Common,
                                layers::Vector{<:Tuple{LayerDefinition, Optional{LayerMesh}, AbstractLayerRendererLayer}},
                                scene::Scene,
                                pass_info::PassInfo)
    for (layer_def, layer_mesh, layer_assets::LayerRendererLayer_Common) in layers
        #TODO: Set up and draw the correct Program for this layer
    end
end

###################################################



#TODO: Rough (i.e. OrenNayar)
#TODO: Transparent (CookTorrance with transparency; no refraction)
#TODO: Refractive