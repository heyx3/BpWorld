#TODO: Turn renderer_cache.jl into a general B+ disk-cache utility

"Checks all associated files' last modified timestamp, and returns whether any of them actually changed"
function check_disk_modifications! end


##  FileAssociations  ##

"A set of files, and their last-known values for 'last time modified'"
const FileAssociations = Dict{AbstractString, DateTime}

function check_disk_modifications!(fa::FileAssociations)::Bool
    any_changes::Bool = false
    for file_path in keys(fa)
        last_changed_time = unix2datetime(isfile(file_path) ?
                                            stat(file_path).mtime :
                                            zero(Float64))
        if last_changed_time > fa[file_path]
            #TODO: Are we sure it's officially legal to change values while iterating over the keys?
            fa[file_path] = last_changed_time
            any_changes = true
        end
    end
    return any_changes
end


##  CachedRenderer  ##

"The range of possible wait times between each file modification check for a voxel layer file"
const DISK_CHECK_INTERVAL_MS = 3000:5000

"A specific loaded version of a `LayerMaterial`"
mutable struct CachedRenderer
    instance::LayerMaterial

    files::FileAssociations
    source_full_path::AbstractString

    last_check_time::DateTime
    # The frequency of checking the disk is randomized for each renderer,
    #    to spread out the latency of querying hard drive information.
    disk_check_interval::Millisecond

    "Creates a CachedRenderer with the given type/initial instance, referencing the given set of files"
    CachedRenderer(instance,
                   file_paths,
                   source_full_path,
                   last_check_time,
                   disk_check_interval = Millisecond(rand(DISK_CHECK_INTERVAL_MS))
                  ) = new(
        instance,
        file_paths, source_full_path,
        last_check_time, disk_check_interval
    )
end

Base.close(c::CachedRenderer) = close(c.instance)

function check_disk_modifications!(c::CachedRenderer)::Bool
    if (now() - c.last_check_time) >= c.disk_check_interval
        c.last_check_time = now()
        return check_disk_modifications!(c.files)
    else
        return false
    end
end


##  RendererCache  ##

"The identifier for the fallback 'error' voxel layer"
const ERROR_LAYER_PATH = "ERR/err.json"

"
Tracks any `LayerRenderer`s that have been referenced so far,
    and automatically updates them as needed.

Similarly tracks depth renderers.
"
mutable struct RendererCache
    error_material::LayerMaterial
    layers::Dict{AbstractString, CachedRenderer}

    # Buffers, used internally for certain functions.
    buf_keys::Vector{AbstractString}
end

"Initializes a new instance. Must be run from within a B+ GL context!"
function RendererCache()
    @bp_check(exists(get_context()), "Can't create a RendererCache without a B+ GL context")

    # Generate the fallback "error" layer.
    error_layer_path = joinpath(VOXEL_LAYERS_PATH, ERROR_LAYER_PATH)
    error_layer_data = open(error_layer_path) do f
        JSON3.read(f, LayerData)
    end
    error_layer_renderer = LayerMaterial(error_layer_data)

    return RendererCache(
        error_layer_renderer,
        Dict{AbstractString, CachedRenderer}(),
        AbstractString[ ]
    )
end

function Base.close(r::RendererCache)
    close.(c for c in values(r.layers) if (c.instance != r.error_material))
    close(r.error_material)
    return nothing
end

function check_disk_modifications!(cache::RendererCache)::Bool
    any_changes::Bool = false
    empty!(cache.buf_keys)
    append!(cache.buf_keys, keys(cache.layers))
    for layer_name in cache.buf_keys
        renderer = cache.layers[layer_name]
        if check_disk_modifications!(renderer)
            #NOTE: If the file no longer exists, this would be the place to delete the renderer.
            #      For now I'm not bothering, as this isn't very common
            #          and restarting the software will clean things up.
            try_load_renderer!(renderer, cache.error_material)
            any_changes = true
        end
    end
    return any_changes
end

"
Gets the material with the given name.
If the file has been changed, then the cache may reload it before returning.
"
function get_material!(cache::RendererCache, layer_path::AbstractString
                      )::LayerMaterial
    # Load it if it hasn't been yet.
    if !haskey(cache.layers, layer_path)
        new_renderer = CachedRenderer(
            cache.error_material,
            FileAssociations(),
            joinpath(VOXEL_LAYERS_PATH, layer_path),
            unix2datetime(0) # Arbitrary time far in the past
        )
        cache.layers[layer_path] = new_renderer
        try_load_renderer!(new_renderer, cache.error_material)
    end

    return cache.layers[layer_path].instance
end

"Attempts to reload the renderer within the given cache"
function try_load_renderer!(cache::CachedRenderer, error_material::LayerMaterial)
    # Load the new material.
    # If anything goes wrong, fall back to the error material.
    local new_mat::LayerMaterial
    try
        layer_data::LayerData = open(cache.source_full_path, "r") do f
            JSON3.read(f, LayerData)
        end
        new_mat = LayerMaterial(layer_data)
        # The material compiled successfully, so update the list of file associations.
        cache.files = Dict(f => unix2datetime(stat(f).mtime) for f in [
            joinpath(VOXEL_LAYERS_PATH, layer_data.frag_shader_path),
            ( joinpath(VOXEL_LAYERS_PATH, t)
                for t in keys(layer_data.textures) )...
        ])
    catch e
        new_mat = error_material
        #TODO: Report the error somehow
        rethrow()
    end

    # Delete the previous version of the material.
    if cache.instance != error_material
        close(cache.instance)
    end

    cache.instance = new_mat
end