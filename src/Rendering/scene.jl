mutable struct Scene
    voxels_array::VoxelGrid
    voxels::Texture # 3D texture of R8
    voxel_meshing::Optional{VoxelMesherTask} # Nulled out once it's finished

    data_buffers::WorldDataBuffers

    sun_shadowmap::Shadowmap
    sky::Sky

    layer_files::Vector{String}
    layer_meshes::Vector{Optional{LayerMesh}}
    viewports::Set{Viewport}
    renderers::Set{AbstractLayerRender}

    renderers_by_model::Dict{Symbol, AbstractLayerRender}

    # Each renderer has some asset data per-layer and per-viewport.
    renderer_layer_assets::Dict{AbstractLayerRenderer, Dict{AbstractString, <:AbstractLayerRendererLayer}}
    renderer_viewport_assets::Dict{AbstractLayerRenderer, Dict{Viewport, <:AbstractLayerRendererViewport}}

    # Caches:
    cache_textures::FileCacher{Texture}
    cache_layers::FileCacher{LayerDefinition}
    cache_error_texture::Texture
    cache_error_layer::LayerDefinition

    # Buffers for various functions:
    internal_layer_texture_views::Vector{Dict{String, Bplus.GL.View}}
    internal_meshing_buffer::VoxelMesher
end
@close_gl_resources(s::Scene,
    s.layers, s.viewports, s.renderers,
    (values(data) for data in lookup for lookup in (s.renderer_layer_assets, s.renderer_viewport_assets))...,
    Iterators.flatten(values(d) for d in values(s.renderer_layer_assets)),
    Iterators.flatten(values(d) for d in values(s.renderer_viewport_assets)),
    (v.instance for v in values(s.cache_textures.files) if (v.instance != s.cache_error_texture)),
    # Individual non-Resource objects that need to be closed:
    tuple(
        s.sky,
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

        WorldDataBuffers(),

        Shadowmap(1024),
        Sky(),

        Vector{String}(), Vector{LayerMesh}(),
        Set{Viewport}(), Set{AbstractLayerRenderer}(),

        Dict{Symbol, AbstractLayerRender}(),
        Dict{AbstractLayerRenderer, Dict{AbstractString, <:AbstractLayerRendererLayer}}(),
        Dict{AbstractLayerRender, Dict{Viewport, <:AbstractLayerRendererViewport}}(),

        cache_textures,
        cache_layers,
        cache_error_texture,
        cache_error_layer,

        Vector{Dict{String, Bplus.GL.View}}(),
        VoxelMesher()
    )
end


@kwdef struct RenderSettings
    render_sky::Bool = true
end


########################
#  Internal Functions  #
########################

"A special layer file path that represents the 'error' layer"
const ERROR_LAYER_FILE = "^%/ERROR_LAYER/%^"

get_layer_data(scene::Scene, path::String) = if path == ERROR_LAYER_FILE
    scene.cache_error_layer
else
    get_cached_data!(scene.cache_layers, path)
end


"Gets the renderer for the given lighting model, creating one if needed"
function ensure_renderer(scene::Scene, model_name::Symbol, model::AbstractLayerDataLightingModel)::AbstractLayerRenderer
    return get!(scene.renderers_by_model, model_name) do
        renderer = layer_renderer_init(model, scene)

        push!(scene.renderers, renderer)
        scene.renderer_viewport_assets[renderer] = Dict{Viewport, AbstractLayerRendererViewport}()
        scene.renderer_layer_assets[renderer] = Dict{AbstractString, AbstractLayerRendererLayer}()

        # Register the renderer with all viewports.
        for viewport in scene.viewports
            viewport_data = layer_renderer_init_viewport(renderer, viewport, scene)
            scene.renderer_viewport_assets[renderer][viewport] = viewport_data
        end

        # No existing layers should already require this brand-new renderer.
        for layer_file in scene.layer_files
            layer_data::LayerDefinition = get_layer_data(scene, layer_file)
            @bpworld_assert(lighting_model_serialized_name(typeof(layer_data.lighting_model)) != model_name,
                              "Renderer should already exist for lighting model ", model_name)
        end

        return renderer
    end

    return nothing
end

layer_idx(scene::Scene, layer_name::String) = findfirst(n -> n==layer_name, scene.layer_files)

error("#TODO: Check how shadow-map passes work. They don't even have a viewport do they?")
function render_pass(s::Scene, v::Viewport, pass_info::PassInfo, settings::RenderSettings)
    # Sort renderers by their order.
    #TODO: Re-use a buffer stored in the Scene.
    renderer_orders::Vector{Tuple{AbstractLayerRenderer, Int}} =
        [(layer, layer_renderer_order(layer, pass)) for layer in s.renderers]
    sort!(renderer_orders, by=(tuple->tuple[2]))

    # Run each one.
    for (renderer::AbstractLayerRenderer, _) in renderer_orders
        render_layers(renderer, s, v, pass_info, settings)
    end

    # Render the sky last, to minimize overdraw.
    if settings.render_sky && (pass_info.type in (Pass.forward, ))
        render_sky(s.sky, pass_info.elapsed_seconds)
    end
end
function render_layers(renderer::AbstractLayerRenderer,
                       scene::Scene, v::Viewport,
                       pass_info::PassInfo, settings::RenderSettings)
    # Make sure the viewport is set up correctly.
    if layer_renderer_reads_target(renderer, pass_info)
        viewport_swap(v)
    end
    target_activate(v.target_current.target)

    # Gather the relevant layer data.
    #TODO: Re-use buffers (stored in the Scene) for this work.
    relevant_layer_idcs::Vector{Int} = sort((layer_idx(scene, n) for n in keys(scene.renderer_layer_assets[renderer])))
    relevant_layer_data = map(relevant_layer_idcs) do i
        return (
            i,
            get_layer_data(scene, scene.layer_files[i]),
            scene.layer_meshes[i],
            scene.internal_layer_texture_views[i],
            scene.renderer_layer_assets[renderer][scene.layer_files[i]]
        )
    end

    # Hand all the data off to the renderer.
    layer_renderer_execute(
        renderer,
        v, scene.renderer_viewport_assets[renderer][v],
        relevant_layer_data,
        scene, pass_info
    )
end


#######################
#  Interface: voxels  #
#######################

"Initializes a new layer into the scene and returns it. Destroy it with `remove_layer()`."
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
"Cleans up a layer (created with `add_layer()`) and removes it from the scene"
function remove_layer(scene::Scene, layer_data_path::String)
    layer_data::LayerDefinition = get_layer_data(scene, layer_data_path)
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

"Refreshes this scene to start using the given voxel generator and layer file paths"
function reset_scene(scene::Scene,
                     generator::Voxels.AbstractVoxelGenerator,
                     new_layer_files::AbstractVector{<:AbstractString},
                     voxel_resolution::Vec3{<:Integer})
    # (Re)start the scene meshing task.
    if exists(scene.voxel_meshing)
        close(scene.voxel_meshing)
    end
    scene.voxel_meshing = VoxelMesherTask(voxel_resolution, generator,
                                          length(new_layer_files),
                                          scene.internal_meshing_buffer)

    # Remove old layers and add new ones.
    # Preserve the layers that stuck around.
    unused_layers = setdiff(Set(scene.layer_files), new_layer_files)
    extra_layers = setdiff(Set(new_layer_files), scene.layer_files)
    for old_layer in unused_layers
        remove_layer(scene, old_layer)
    end
    for new_layer in extra_layers
        add_layer(scene, new_layer)
    end
end


##########################
#  Interface: rendering  #
##########################

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
"Cleans up a viewport (created with `add_viewport()`) and removes it from the scene"
function remove_viewport(scene::Scene, viewport::Viewport)
    @bp_check(viewport in scene.viewports, "Viewport doesn't exist in the scene")

    # Clean up the renderers' viewport-specific data.
    for renderer in scene.renderers
        layer_renderer_close_viewport(renderer, viewport, scene.renderer_viewport_assets[viewport], scene)
    end

    delete!(scene.viewports, viewport)
    close(viewport)
end

function begin_scene_frame(s::Scene,
                           delta_seconds::Float32, total_elapsed_seconds::Float32,
                           sun_data::@NamedTuple{dir::v3f, color::vRGBf, shadow_bias::Float32},
                           fog_data::UniformBlock_Fog)
    # Update uniform buffers.
    set_buffer_data(s.data_buffers.buf_fog, Ref(fog_data))
    set_buffer_data(s.data_buffers.buf_sun, Ref(UniformBlock_Sun(
        vappend(sun_data.dir, @f32(0)), vappend(sun_data.color, @f32(0)),
        get_ogl_handle(get_view(s.sun_shadowmap.depth_texture)),
        shadow_bias,
        s.sun_shadowmap.mat_world_to_texel
    )))

    # Update file caches.
    check_disk_modifications!(scene.cache_layers)
    check_disk_modifications!(scene.cache_textures)

    # Update any meshing work going on.
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

    # Render shadowmaps.
    prepare(s.sun_shadowmap, s.sun.dir.xyz,
            Box3Df(min=zero(v3f), size=vsize(s.voxels_array)))
    render_pass(s, v,
                PassInfo(Pass.shadow_map, total_elapsed_seconds),
                RenderSettings(render_sky=false))
    finish(s.sun_shadowmap)

    # Gather the textures to use for each layer from file caches.
    n_layers::Int = length(s.layer_files)
    # Re-use buffers as much as possible.
    while length(s.internal_layer_texture_views) < n_layers
        push!(s.internal_layer_texture_views, Dict{String, Bplus.GL.View}())
    end
    for (layer_path, layer_textures_lookup) in zip(s.layer_files, s.internal_layer_texture_views)
        layer_data::LayerDefinition = get_layer_data(s, layer_path)
        for (tex_path, tex_settings::LayerDataTexture) in layer_data.textures
            texture::Texture = get_cached_data!(s.cache_textures, tex_path)
            sampler::Optional{TexSampler{2}} = tex_settings.sampler
            layer_textures_lookup[tex_settings.code_name] = get_view(texture, sampler)
        end
    end

    # Activate the texture views for all layer textures.
    for layer_textures in @view(s.internal_layer_texture_views[1:n_layers])
        for view in values(layer_textures)
            view_activate(view)
        end
    end
    # Activate the voxel data texture if there are any non-meshed layers, who need it.
    if any(isnothing, s.layer_meshes)
        view_activate(s.voxels)
    end
end
function end_scene_frame(s::Scene)
    # Deactivate texture views for all layer textures, and the voxel data texture if it was activated.
    for layer_textures in @view(s.internal_layer_texture_views[1:n_layers])
        for view in values(layer_textures)
            view_deactivate(views)
        end
        empty!(layer_textures)
    end
    view_deactivate(s.voxels)
end

"
Make sure to call `begin_scene_frame()` before invoking this function,
    and `end_scene_frame()` after rendering all your viewports
"
function render_viewport(s::Scene, v::Viewport, total_elapsed_seconds::Float32,
                         settings::RenderSettings)
    # Provide the viewport data as a uniform buffer.
    set_buffer_data(s.data_buffers.buf_viewport, Ref(UniformBlock_Viewport(v.cam)))

    viewport_clear(v)

    # Run the depth pre-pass.
    viewport_each_target(v) do vt::ViewportTarget
        target_configure_fragment_outputs(vt.target, Vec{0, Int}())
    end
    render_pass(s, v, PassInfo(Pass.depth, total_elapsed_seconds), settings)

    # Run the forward pass.
    viewport_each_target(v) do vt::ViewportTarget
        n_color_attachments = length(vt.target.attachment_colors)
        target_configure_fragment_outputs(vt.target, collect(1:n_color_attachments))
    end
    render_pass(s, v, PassInfo(Pass.forward, total_elapsed_seconds), settings)

    #TODO: Bloom
    #TODO: Post effects
    #TODO: Tonemap with col = col / (col + 1)
end