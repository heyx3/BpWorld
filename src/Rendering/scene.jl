mutable struct Scene
    voxels::Texture # 3D texture of R8
    layers::Vector{Layer}

    sun::UniformBlock_Sun
    fog::UniformBlock_Fog
end

#TODO: Tick scene