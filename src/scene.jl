mutable struct Scene
end
function Base.close(s::Scene)
end

function Scene(assets::Assets)
    return Scene()
end