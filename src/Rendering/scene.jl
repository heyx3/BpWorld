"A renderable voxel world, and the viewports that are rendering it"
mutable struct Scene
    voxels_array::AbstractVoxelGrid
    voxels::Texture # 3D texture of R8Uint
    voxel_meshing::Optional{VoxelMesherTask} # Nulled out once it's finished

    data_buffers::WorldDataBuffers

    sun_shadow_viewport::Optional{Viewport} # Has to be set up after creation
    sun_shadow_matrix_world_to_texel::fmat4
    sky::Sky

    layer_files::Vector{String}
    layer_meshes::Vector{Optional{LayerMesh}}
    viewports::Set{Viewport}
    renderers::Set{AbstractLayerRenderer}

    renderers_by_model::Dict{Symbol, AbstractLayerRenderer}

    # Each renderer has some asset data per-layer and per-viewport.
    # Layers are indexed by file path.
    #TODO: Use Symbol instead of String for layer names
    renderer_layer_assets::Dict{AbstractLayerRenderer, Dict{AbstractString, <:AbstractLayerRendererLayer}}
    renderer_viewport_assets::Dict{AbstractLayerRenderer, Dict{Viewport, <:AbstractLayerRendererViewport}}

    # Caches:
    cache_textures::Bplus.FileCacher{Texture}
    cache_layers::FileCacher{LayerDefinition}
    cache_error_texture::Texture
    cache_error_layer::LayerDefinition

    # Buffers for various functions:
    internal_layer_texture_views::Vector{Dict{String, Bplus.GL.View}}
    internal_used_textures::Dict{Tuple{String, Optional{Bplus.GL.TexSampler{2}}}, Bplus.GL.View}
    internal_meshing_buffer::VoxelMesher
end
Base.close(s::Scene) = close.([
    (layer_assets    for (renderer,    layers) in s.renderer_layer_assets    for (layer_path,  layer_assets) in layers)...,
    (viewport_assets for (renderer, viewports) in s.renderer_viewport_assets for (viewport, viewport_assets) in viewports)...,
    s.renderers...,
    s.viewports...,
    s.sky,
    s.voxels,
    (file_cache.instance::Texture for (abs_path, file_cache) in s.cache_textures.files)...,
    (exists(s.voxel_meshing) ? tuple(s.voxel_meshing) : tuple())...
])

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
        LightingModel_Common(),
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
            return open(path) do io
                result = JSON3.read(io, LayerDefinition)
                dependencies = tuple(
                    joinpath(VOXEL_LAYERS_PATH, result.frag_shader_path)
                )
                return (result, dependencies)
            end
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

    scene = Scene(
        Array{VoxelElement}(undef, 0, 0, 0),
        Texture(SimpleFormat(FormatTypes.uint, SimpleFormatComponents.R, SimpleFormatBitDepths.B8),
                one(v3u)),
        nothing,

        WorldDataBuffers(),

        nothing, m_identityf(4, 4),
        Sky(),

        Vector{String}(), Vector{LayerMesh}(),
        Set{Viewport}(), Set{AbstractLayerRenderer}(),

        Dict{Symbol, AbstractLayerRenderer}(),
        Dict{AbstractLayerRenderer, Dict{AbstractString, <:AbstractLayerRendererLayer}}(),
        Dict{AbstractLayerRenderer, Dict{Viewport, <:AbstractLayerRendererViewport}}(),

        cache_textures,
        cache_layers,
        cache_error_texture,
        cache_error_layer,

        Vector{Dict{String, Bplus.GL.View}}(),
        Dict{Tuple{String, Optional{Bplus.GL.TexSampler{2}}}, Bplus.GL.View}(),
        VoxelMesher()
    )

    # Set up the sunlight shadow-map's viewport.
    scene_bounds = Box3Df(min=zero(v3f), size=vsize(scene.voxels_array))
    shadowmap_transform = get_shadowmap_transform(vnorm(v3f(1, 1, -1)), scene_bounds)
    scene.sun_shadow_viewport = add_viewport(
        scene, shadowmap_transform.cam,
        resolution=v2i(2048, 2048),
        fix_aspect_ratio=false
    )
    scene.sun_shadow_matrix_world_to_texel = shadowmap_transform.world_to_texel

    return scene
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
function ensure_renderer(scene::Scene, model_name::Symbol, model_def::AbstractLayerDataLightingModel)::AbstractLayerRenderer
    return get!(scene.renderers_by_model, model_name) do
        renderer = layer_renderer_init(model_def, scene)

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

function render_pass(s::Scene, v::Viewport, pass_info::PassInfo, settings::RenderSettings)
    # Sort renderers by their order.
    #TODO: Re-use a buffer stored in the Scene.
    renderer_orders::Vector{Tuple{AbstractLayerRenderer, Int}} =
        [(layer, layer_renderer_order(layer, pass_info)) for layer in s.renderers]
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
    # Gather the relevant layer data.
    #TODO: Re-use buffers (stored in the Scene) for this work.
    relevant_layer_idcs::Vector{Int} = sort(collect(
        layer_idx(scene, n) for n in keys(scene.renderer_layer_assets[renderer])
    ))
    relevant_layer_data = map(relevant_layer_idcs) do i
        return LayerRenderExecution(
            i,
            get_layer_data(scene, scene.layer_files[i]),
            scene.layer_meshes[i],
            scene.internal_layer_texture_views[i],
            scene.renderer_layer_assets[renderer][scene.layer_files[i]]
        )
    end

    # Hand all the data off to the renderer.
    sample_prev_target::Bool = layer_renderer_reads_target(renderer, pass_info)
    if sample_prev_target
        viewport_swap(v)
        viewport_activate_samplers(v.target_previous)
    end
    target_activate(v.target_current.target)
    layer_renderer_execute(
        renderer,
        v, scene.renderer_viewport_assets[renderer][v],
        relevant_layer_data,
        scene, pass_info
    )
    if sample_prev_target
        viewport_deactivate_samplers(v.target_previous)
    end
end


#######################
#  Interface: voxels  #
#######################

"Initializes a new layer into the scene and returns it. Destroy it with `remove_layer()`."
function add_layer(scene::Scene, layer_data_path::String)::LayerDefinition
    layer_data::LayerDefinition = get_cached_data!(scene.cache_layers, layer_data_path)

    # Get/create the correct renderer and tell it about this new layer.
    lighting_model_name::Symbol = lighting_model_serialized_name(typeof(layer_data.lighting_model))
    renderer = ensure_renderer(scene, lighting_model_name, layer_data.lighting_model)
    scene.renderer_layer_assets[renderer][layer_data_path] = layer_renderer_init_layer(
        renderer, layer_data, scene
    )

    # Push the layer into the scene.
    push!(scene.layer_files, layer_data_path)
    push!(scene.layer_meshes, nothing)
    layer_idx::Integer = length(scene.layer_files)

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
    deleteat!(scene.layer_files, layer_idx)
    if exists(scene.layer_meshes[layer_idx])
        close(scene.layer_meshes[layer_idx])
    end
    deleteat!(scene.layer_meshes, layer_idx)

    return nothing
end


"
Grabs the `#layer N path/to/layer.json` statements from the given scene file.
Returns the scene file with those statements stripped (leaving only the DSL),
    and the contents of those statements.
"
function grab_layers(contents::AbstractString
                    )::Tuple{typeof(contents),
                             Dict{VoxelElement, typeof(contents)}}
    layers = Dict{VoxelElement, AbstractString}()
    rgx = r"(?m)^#layer\s+([0-9]+)\s+(.+)$"
    for match in eachmatch(rgx, contents)
        (layer_idx, layer_relative_path) = match.captures
        layer_idx = parse(VoxelElement, layer_idx)
        @bp_check(!haskey(layers, layer_idx),
                  "Layer ", layer_idx, " is named more than once: ",
                    "\"", layer_relative_path, "\" and then \"",
                    layers[layer_idx], "\"")
        layers[layer_idx] = layer_relative_path
    end
    return (replace(contents, rgx=>""), layers)
end

"Refreshes this scene to start using the given voxel generator and layer file paths"
function reset_scene(scene::Scene,
                     generator::Generation.AbstractVoxelGenerator,
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
"
Processes a new scene file in the background, eventually replacing the current scene with it.
If the scene file is invalid, returns an error message.
Otherwise, returns `nothing` to indicate that it was accepted.
"
function start_new_scene(renderer::Scene, new_contents::AbstractString,
                         voxel_resolution::v3i
                        )::Optional{AbstractString}
    # As soon as something fails, roll back the changes and exit.

    # Parse voxel layers.
    local new_layers::Dict{VoxelElement, AbstractString}
    try
        (new_contents, new_layers) = grab_layers(new_contents)
    catch e
        return "Layer error: $(sprint(showerror, e))"
    end
    ordered_layers = sort!(collect(new_layers), by=kvp->kvp[1])

    # Arrange the layers into an array.
    # For missing/unused voxel values, reference the Error renderer.
    max_layer_idx = maximum(keys(new_layers))
    layer_list::Vector{<:AbstractString} = map(1:max_layer_idx) do layer_value
        return get(new_layers, layer_value, ERROR_LAYER_FILE)
    end

    # Parse the voxel generator.
    local scene_expr
    try
        scene_expr = Meta.parseall(new_contents)
    catch e
        return "Scene has invalid syntax $(sprint(showerror, e))"
    end

    # Evaluate the voxel generator expression.
    scene_generator = Generation.eval_dsl(scene_expr)
    if scene_generator isa Generation.DslError
        return string(scene_generator.msg_data...)
    elseif !isa(scene_generator, Generation.AbstractVoxelGenerator)
        return "Output of the scene is not a voxel generator! It's a $(typeof(scene_generator))"
    end

    # Everything loaded and parsed correctly, so kick off the scene generation.
    reset_scene(renderer, scene_generator, layer_list, voxel_resolution)

    return nothing
end



##########################
#  Interface: rendering  #
##########################

"Initializes a new viewport into the scene and returns it. Destroy it with `remove_viewport()`."
function add_viewport( scene::Scene,
                       cam::Cam3D{Float32},
                       settings::Cam3D_Settings{Float32} = Cam3D_Settings{Float32}()
                       ;
                       resolution::v2i = Bplus.GL.get_window_size(),
                       fix_aspect_ratio::Bool = true
                     )::Viewport
    # Create the viewport.
    viewport = let view_cam = cam
        if fix_aspect_ratio
            @set! view_cam.projection.aspect_width_over_height = resolution.x / @f32(resolution.y)
        end
        Viewport(view_cam, settings, resolution)
    end

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
        layer_renderer_close_viewport(renderer, viewport,
                                      scene.renderer_viewport_assets[renderer][viewport],
                                      scene)
        delete!(scene.renderer_viewport_assets[renderer], viewport)
    end

    delete!(scene.viewports, viewport)
    close(viewport)
end

"
Call this once per program frame, paired with a call to `end_scene_frame()`.
Render any number of viewports between the two calls with `render_viewport()`.
"
function begin_scene_frame(scene::Scene,
                           delta_seconds::Float32, total_elapsed_seconds::Float32,
                           sun_data::@NamedTuple{dir::v3f, color::vRGBf, shadow_bias::Float32},
                           fog_data::UniformBlock_Fog)
    # Update uniform buffers.
    set_buffer_data(scene.data_buffers.buf_fog, fog_data)

    # Update file caches.
    check_disk_modifications!(scene.cache_layers)
    check_disk_modifications!(scene.cache_textures)

    # Update any meshing work going on.
    update_meshing(
        scene.voxel_meshing,
        new_grid::AbstractVoxelGrid -> begin
            println("Voxel scene is completed! Uploading into texture...")
            scene.voxels_array = new_grid
            @time set_tex_color(scene.voxels, scene.voxels_array)
            println()
        end,
        (layer_idx::Int, layer_buffers::VoxelMesher) -> begin
            println("Layer ", layer_idx, " is done meshing.")
            if layer_buffers.n_indices > 0 # Don't bother generating an empty mesh
                println("\tUploading into buffers...")
                @time(scene.layer_meshes[layer_idx] = LayerMesh(layer_buffers))
                println()
            end
        end
    )

    # Gather the textures to use for each layer from file caches.
    n_layers::Int = length(scene.layer_files)
    @bp_check(isempty(scene.internal_used_textures))
    # Re-use buffers as much as possible.
    while length(scene.internal_layer_texture_views) < n_layers
        push!(scene.internal_layer_texture_views, Dict{String, Bplus.GL.View}())
    end
    for (layer_path, layer_textures_lookup) in zip(scene.layer_files, scene.internal_layer_texture_views)
        layer_data::LayerDefinition = get_layer_data(scene, layer_path)
        for (tex_path, tex_settings::LayerDataTexture) in layer_data.textures
            texture::Texture = get_cached_data!(scene.cache_textures, tex_path)
            sampler::Optional{Bplus.GL.TexSampler{2}} = tex_settings.sampler
            view = get_view(texture, sampler)

            layer_textures_lookup[tex_settings.code_name] = view
            scene.internal_used_textures[(tex_path, sampler)] = view
        end
    end

    # Activate the texture views for all layer textures.
    for ((tex_file_path, tex_sampler), tex_view) in scene.internal_used_textures
        view_activate(tex_view)
    end
    # Activate the voxel data texture if there are any non-meshed layers; they need it.
    if any(isnothing, scene.layer_meshes)
        view_activate(scene.voxels)
    end

    # Render shadowmaps.
    #  1) compute sun's transform matrices
    scene_bounds = Box3Df(min=zero(v3f), size=vsize(scene.voxels_array))
    shadowmap_transform = get_shadowmap_transform(sun_data.dir, scene_bounds)
    scene.sun_shadow_matrix_world_to_texel = shadowmap_transform.world_to_texel
    #  2) execute the shadowmap render pass.
    #TODO: Re-use one instance of UniformBlock_Sun
    set_buffer_data(scene.data_buffers.buf_sun, UniformBlock_Sun(
        vappend(sun_data.dir, @f32(0)), vappend(sun_data.color, @f32(0)),
        get_ogl_handle(get_view(scene.sun_shadow_viewport.target_current.depth)),
        sun_data.shadow_bias,
        scene.sun_shadow_matrix_world_to_texel
    ))
    set_buffer_data(scene.data_buffers.buf_viewport,
                    #TODO: Re-use one instance of UniformBlock_Viewport
                    UniformBlock_Viewport(scene.sun_shadow_viewport.cam))
    viewport_clear(scene.sun_shadow_viewport)
    render_pass(scene, scene.sun_shadow_viewport,
                PassInfo(Pass.shadow_map, total_elapsed_seconds),
                RenderSettings(render_sky=false))
end

"
Call this once per program frame, paired with a call to `begin_scene_frame()`.
Render any number of viewports between the two calls with `render_viewport()`.
"
function end_scene_frame(scene::Scene)
    # Deactivate texture views for all layer textures, and the voxel data texture if it was activated.
    for ((tex_file_path, tex_sampler), tex_view) in scene.internal_used_textures
        view_deactivate(tex_view)
    end
    empty!(scene.internal_used_textures)
    view_deactivate(scene.voxels)
    # Empty out the per-layer texture collections, but keep them around for re-use next frame.
    for layer_textures in @view(scene.internal_layer_texture_views[1:length(scene.layer_files)])
        empty!(layer_textures)
    end
end

"
Make sure to call `begin_scene_frame()` before invoking this function,
    and `end_scene_frame()` after rendering all your viewports
"
function render_viewport(s::Scene, v::Viewport, total_elapsed_seconds::Float32,
                         settings::RenderSettings)
    # Provide the viewport data as a uniform buffer.
    set_buffer_data(s.data_buffers.buf_viewport, UniformBlock_Viewport(v.cam))

    viewport_clear(v)

    # Run the depth pre-pass.
    viewport_each_target(v) do vt::ViewportTarget
        target_configure_fragment_outputs(vt.target, Vec{0, Int}())
    end
    render_pass(s, v, PassInfo(Pass.depth, total_elapsed_seconds), settings)

    if !v.depth_only
        # Run the forward pass.
        viewport_each_target(v) do vt::ViewportTarget
            n_color_attachments = length(vt.target.attachment_colors)
            target_configure_fragment_outputs(vt.target, vt.target_all_color_attachments)
        end
        render_pass(s, v, PassInfo(Pass.forward, total_elapsed_seconds), settings)

        #TODO: Bloom
        #TODO: Post effects
        #TODO: Tonemap with col = col / (col + 1)
    end
end