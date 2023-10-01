"A set of textures representing the output of the scene render"
struct ViewportTarget
    color::Texture
    emissive_strength::Texture
    depth::Texture

    target::Target
end
@close_gl_resources(t::ViewportTarget)

#TODO: Constructor, given a resolution


mutable struct Viewport
    cam::Cam3D{Float32}
    cam_settings::Cam3D_Settings{Float32}

    # Ping-pong between targets as needed (e.x. refractive materials want the result of opaque rendering)
    target_current::ViewportTarget
    target_previous::ViewportTarget
end
@close_gl_resources(v::Viewport, (v.target_current, v.target_previous))

#TODO: Constructor, given a resolution
#TODO: Resize function