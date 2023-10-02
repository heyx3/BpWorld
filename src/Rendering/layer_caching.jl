#TODO: Provide caching as a B+ service
#TODO: Texture caching too

# Layers are loaded from disk.
# They are automatically re-loaded as their definition files change.
make_layer_cacher() = FileCacher{LayerData}(
    error_response = (path, exception, trace) -> begin
        Bplus.Helpers.default_cache_error_response(path, exception, trace)
        return 
    end
)

function Bplus.Helpers.load_uncached_data(::Type{Layer}, path)
    data = open(io -> JSON3.read(io, LayerDefinition), path)
    return Layer(
        data,
        layer_renderer_init
    )
end