mutable struct PostProcess

end

function Base.close(p::PostProcess)
    # Try to close() everything that isnt specifically blacklisted.
    # This is the safest option to avoid leaks.
    blacklist = tuple()
    whitelist = setdiff(fieldnames(typeof(p)), blacklist)
    for field in whitelist
        close(getfield(p, field))
    end
end

function PostProcess(window::GLFW.Window, assets::Assets, scene::Scene)
    return PostProcess()
end