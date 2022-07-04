mutable struct PostProcess

end

function Base.close(p::PostProcess)
end

function PostProcess(assets::Assets, scene::Scene)
    return PostProcess()
end