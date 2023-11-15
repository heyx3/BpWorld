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
    # Generate declarations from the user data.
    frag_defines = sprint() do io::IO
        for (name, value) in l.preprocessor_defines
            print(io, "#define ", name, " ", value, "\n")
        end
        for tex_data::LayerDataTexture in values(l.textures)
            print(io, "uniform sampler2D ", tex_data.code_name, ";\n")
        end
    end

    # Load the custom fragment shader.
    fragment_shader_body = read(joinpath(VOXEL_LAYERS_PATH,
                                         data.frag_shader_path),
                                String)

    # Load/generate shader source.
    (vert_preview, vert_meshed, geom_preview, frag_forward, frag_depth) = process_shader_contents.((
        SHADER_PREVIEW_VERT, SHADER_MESHED_VERT, SHADER_PREVIEW_GEOM,

        replace("""
        $COMMON_MODEL_FRAG_SHADER_HEADER_FORWARD
        $frag_defines
        #line 0
        $fragment_shader_body
        """, "\n        "=>"\n"),

        replace("""
        #line 10000
        $COMMON_MODEL_FRAG_SHADER_HEADER_DEPTH
        #line 1000
        $frag_defines
        #line 0
        $fragment_shader_body
        """, "\n        "=>"\n"),
    ))

    # Compile programs.
    return LayerRendererLayer_Common(
        Program(vert_preview, frag_depth; geom_shader=geom_preview),
        Program(vert_meshed, frag_depth),
        Program(vert_preview, frag_forward; geom_shader=geom_preview),
        Program(vert_meshed, frag_forward)
    )
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
                                layers::Vector{<:Tuple{Int, LayerDefinition, Optional{LayerMesh}, AbstractLayerRendererLayer}},
                                scene::Scene,
                                pass_info::PassInfo)
    mat_viewproj = m_combine(cam_view_mat(viewport.cam),
                             cam_projection_mat(viewport.cam))
    # Set some global render state.
    let c = get_context()
        c.cull_mode = FaceCullModes.off #TODO: Test that meshes and previews are both generated with correct orientation
        c.blend_mode = (
            rgb = make_blend_opaque(BlendStateRGB),
            alpha = BlendStateAlpha(
                BlendFactors.zero,
                BlendFactors.one,
                BlendOps.add
            )
        )
        c.depth_write = true
        if pass_info.type in (Pass.depth, Pass.shadow_map)
            c.color_write_mask = zero(v4b)
        end
    end

    for (layer_idx::Int, layer_def, layer_mesh, layer_assets::LayerRendererLayer_Common) in layers
        # Decide which shader to use for this pass and layer.
        has_mesh::Bool = exists(layer_mesh)
        depth_only = (pass_info.type in (Pass.depth, Pass.shadow_map))
        prog::Program = (layer_assets.depth_preview, layer_assets.depth_meshed,
                         layer_assets.forward_preview, layer_assets.forward_meshed
                        )[1 + (has_mesh ? 1 : 0) + (depth_only ? 0 : 2)]

        # Set global uniforms.
        set_universal_uniforms(prog,
                               zero(v3f), v3f(10, 10, 10),
                               pass_info.elapsed_seconds,
                               mat_viewproj)
        if isnothing(layer_mesh)
            set_preview_uniforms(prog,
                                 convert(v3u, vsize(scene.voxels_array)),
                                 layer_idx,
                                 scene.voxels)
            # Note that texture activation (and later deactivation) isn't handled by us,
            #    but by the scene.
        end

        # Set texture uniforms.
        for (tex_file, tex_data) in layer_def.textures
            uniform_name = tex_data.code_name

            tex = get_cached_data!(scene.cache_textures, tex_file)
            tex_view = get_view(tex, tex_data.sampler)
            # Note that texture activation (and later deactivation) isn't handled by us,
            #    but by the scene.

            set_uniform(prog, uniform_name, tex_view)
        end

        # Draw.
        if has_mesh
            render_mesh(layer_mesh, prog)
        else
            render_mesh(
                service_BasicGraphics().empty_mesh, prog
                ;
                shape = PrimitiveTypes.point,
                indexed_params = nothing,
                elements = IntervalU(
                    min=1,
                    size=prod(vsize(scene.voxels_array))
                )
            )
        end
    end
end

###################################################



#TODO: Rough (i.e. OrenNayar)
#TODO: Transparent (CookTorrance with transparency; no refraction)
#TODO: Refractive