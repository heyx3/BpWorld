mutable struct Scene
    voxels_array::VoxelGrid
    voxels::Texture # 3D texture of R8
    voxel_meshing::Optional{VoxelMesherTask} # Nulled out once it's finished

    sun::UniformBlock_Sun
    fog::UniformBlock_Fog

    layer_files::Vector{String}
    layer_meshes::Vector{Optional{LayerMesh}}
    viewports::Set{Viewport}
    renderers::Set{AbstractLayerRender}

    renderers_by_model::Dict{Symbol, AbstractLayerRender}

    # Each renderer has some asset data per-layer and per-viewport.
    renderer_layer_assets::Dict{AbstractLayerRenderer, Dict{Int, <:AbstractLayerRendererLayer}}
    renderer_viewport_assets::Dict{AbstractLayerRenderer, Dict{Viewport, <:AbstractLayerRendererViewport}}

    # Caches:
    cache_textures::FileCacher{Texture}
    cache_layers::FileCacher{LayerDefinition}
    cache_error_texture::Texture
    cache_error_layer::LayerDefinition
end
@close_gl_resources(s::Scene,
    s.layers, s.viewports, s.renderers,
    (values(data) for data in lookup for lookup in (s.renderer_layer_assets, s.renderer_viewport_assets))...,
    Iterators.flatten(values(d) for d in values(s.renderer_layer_assets)),
    Iterators.flatten(values(d) for d in values(s.renderer_viewport_assets)),
    (v.instance for v in values(s.cache_textures.files) if (v.instance != s.cache_error_texture)),
    # Individual non-Resource objects that need to be closed:
    tuple(
        @optional(exists(s.voxel_meshing), s.voxel_meshing)
    )
)

function Scene()
    # Define fallback data for the caches.
    cache_error_texture = Texture(
        SimpleFormat(FormatTypes.normalized_uint, SimpleFormatComponents.RGBA, SimpleFormatBitDepths.B8),
        # A 2x2 checkerboard pattern of ugly colors (alpha will automatically be set to 1):
        [
            vRGBf(0, 1, 1) vRGBf(1, 0, 1)
            vRGBf(1, 0, 1) vRGBf(0, 1, 1)
        ]
    )
    cache_error_layer = LayerDefinition(
        "ERR/err.frag",
        :simple_solid,
        Dict(),
        Dict()
    )

    # Configure the caches.
    cache_textures = FileCacher{Texture}(
        reload_response = (path, old::Optional{Texture} = nothing) -> begin
            return load_tex(
                path,
                vRGBAu8,
                SimpleFormat(FormatTypes.normalized_uint, SimpleFormatComponents.RGBA, SimpleFormatBitDepths.B8)
            )
        end,
        error_response = (path, exception, trace, old::Optional{Texture} = nothing) -> begin
            @error(
                "Failed to load texture for $path. $((exists(old) ? "Using previous texture" : "Using Error texture"))",
                ex=(exception, trace)
            )
            return exists(old) ? old : cache_error_texture
        end,
        relative_path = VOXEL_LAYERS_PATH,
        check_interval_ms = 3000:5000
    )
    cache_layers = FileCacher{LayerDefinition}(
        reload_response = (path, old::Optional{LayerDefinition} = nothing) -> begin
            return open(io -> begin
                result = JSON3.read(io, LayerDefinition)
                dependencies = tuple(
                    joinpath(VOXEL_LAYERS_PATH, result.frag_shader_path)
                )
                return (result, dependencies)
            end)
        end,
        error_response = (path, exception, trace, old::Optional{Texture} = nothing) -> begin
            @error(
                "Failed to load layer definition $path. $((exists(old) ? "Using previous version" : "Using a stand-in for now"))",
                ex=(exception, trace)
            )
            return exists(old) ? old : cache_error_layer
        end,
        relative_path = VOXEL_LAYERS_PATH,
        check_interval_ms = 1000:3000
    )

    return new(
        Array{VoxelElement}(undef, 0, 0, 0),
        Texture(SimpleFormat(FormatTypes.uint, SimpleFormatComponents.R, SimpleFormatBitDepths.B8),
                one(v3u)),
        nothing,

        UniformBlock_Sun(vnorm(v4f(1, 1, -1)),
                         vRGBAf(1, 0.95, 0.9, 1.0),
                         Ptr_View(),
                         @f32(0.0),
                         m4_identityf()),
        UniformBlock_Fog(@f32(0), @f32(1), @f32(0), @f32(1), one(vRGBAf)),

        Vector{String}(), Vector{LayerMesh}(),
        Set{Viewport}(), Set{AbstractLayerRenderer}(),

        Dict{Symbol, AbstractLayerRender}(),
        Dict{AbstractLayerRenderer, Dict{Int, <:AbstractLayerRendererLayer}}(),
        Dict{AbstractLayerRender, Dict{Viewport, <:AbstractLayerRendererViewport}}(),

        cache_textures,
        cache_layers,
        cache_error_texture,
        cache_error_layer
    )
end


"Gets the renderer for the given lighting model, creating one if needed"
function ensure_renderer(scene::Scene, model_name::Symbol, model::AbstractLayerDataLightingModel)::AbstractLayerRenderer
    return get!(scene.renderers_by_model, model_name) do
        renderer = layer_renderer_init(model, scene)

        push!(scene.renderers, renderer)
        scene.renderer_viewport_assets[renderer] = Dict{Viewport, AbstractLayerRendererViewport}()
        scene.renderer_layer_assets[renderer] = Dict{AbstractLayerRenderer, AbstractLayerRendererLayer}()

        # Register the renderer with all viewports.
        for viewport in scene.viewports
            viewport_data = layer_renderer_init_viewport(renderer, viewport, scene)
            scene.renderer_viewport_assets[renderer][viewport] = viewport_data
        end

        # No existing layers should already require this brand-new renderer.
        for layer_file in scene.layer_files
            layer_data::LayerDefinition = get_cached_data!(scene.cache_layers, layer_file)
            @bpworld_assert(lighting_model_serialized_name(typeof(layer_data.lighting_model)) != model_name,
                              "Renderer should already exist for lighting model ", model_name)
        end

        return renderer
    end

    return nothing
end

"Initializes a new viewport into the scene and returns it. Destroy it with `remove_viewport()`."
function add_viewport( scene::Scene,
                       cam::Cam3D{Float32},
                       settings::Cam3D_Settings{Float32} = Cam3D_Settings{Float32}()
                       ;
                       resolution::v2i = Bplus.GL.get_window_size()
                     )::Viewport
    # Create the viewport.
    @set! cam.aspect_width_over_height = resolution.x / @f32(resolution.y)
    viewport = Viewport(cam, settings, resolution)

    # Register with all renderers.
    for renderer in scene.renderers
        viewport_data = layer_renderer_init_viewport(renderer, viewport, scene)
        scene.renderer_viewport_assets[renderer][viewport] = viewport_data
    end

    push!(scene.viewports, viewport)
    return viewport
end
"Cleans up a viewport and removes it from the scene"
function remove_viewport(scene::Scene, viewport::Viewport)
    @bp_check(viewport in scene.viewports, "Viewport doesn't exist in the scene")

    # Clean up the renderers' viewport-specific data.
    for renderer in scene.renderers
        layer_renderer_close_viewport(renderer, viewport, scene.renderer_viewport_assets[viewport], scene)
    end

    delete!(scene.viewports, viewport)
    close(viewport)
end

function add_layer(scene::Scene, layer_data_path::String)::LayerDefinition
    layer_data::LayerDefinition = get_cached_data!(scene.cache_layers, layer_data_path)

    # Push the layer into the scene.
    push!(scene.layer_files, layer_data_path)
    push!(scene.layer_meshes, nothing)
    layer_idx::Integer = length(scene.layer_files)

    # Tell the corresponding renderer about the new layer.
    lighting_model_name::Symbol = lighting_model_serialized_name(typeof(layer_data.lighting_model))
    renderer = ensure_renderer(scene, lighting_model_name, layer_data.lighting_model)
    scene.renderer_viewport_assets[renderer][layer_idx] = layer_renderer_init_layer(
        renderer, layer_data, scene
    )

    return layer_data
end
function remove_layer(scene::Scene, layer_data_path::String)
    layer_data::LayerDefinition = get_cached_data!(scene.cache_layers, layer_data_path)
    layer_idx = findfirst(path -> layer_data_path == path, scene.layer_files)
    @bpworld_assert(exists(layer_idx), "Couldn't find existing layer for '", layer_data_path, "'")

    # Get the renderer for this layer.
    lighting_model_name::Symbol = lighting_model_serialized_name(typeof(layer_data.lighting_model))
    @bpworld_assert(haskey(scene.renderers_by_model, lighting_model_name),
                    "Lighting mode '", lighting_model_name, "' missing during layer destruction")
    renderer = scene.renderers_by_model[lighting_model_name]

    # Remove layer-specific data from the scene.
    delete!(scene.renderer_viewport_assets[renderer], layer_idx)
    deleteat!(scene.layer_files, layer_idx)
    if exists(scene.layer_meshes[layer_idx])
        close(scene.layer_meshes[layer_idx])
    end
    deleteat!(scene.layer_meshes, layer_idx)

    return nothing
end

function render_viewport(s::Scene, v::Viewport)
    #TODO: Implement
end

function update_scene(s::Scene)
    update_meshing(
        s.voxel_meshing,
        new_grid::VoxelGrid -> begin
            println("Voxel scene is completed! Uploading into texture...")
            s.voxels_array = new_grid
            @time set_tex_color(s.voxels, s.voxels_array)
            println()
        end,
        (layer_idx::Int, layer_buffers::VoxelMesher) -> begin
            println("Layer ", layer_idx, " is done meshing.")
            if layer_buffers.n_indices > 0 # Don't bother generating an empty mesh
                println("\tUploading into buffers...")
                @time(s.layer_meshes[layer_idx] = LayerMesh(layer_buffers))
                println()
            end
        end
    )
end