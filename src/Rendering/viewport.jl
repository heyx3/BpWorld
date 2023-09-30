mutable struct Viewport
    cam::Cam3D{Float32}
    cam_settings::Cam3D_Settings{Float32}

    output::Target
    output_color::Texture
    output_depth::Texture
end

function close(v::Viewport)
    close(v.output)
    close(v.output_color)
    close(v.output_depth)
end