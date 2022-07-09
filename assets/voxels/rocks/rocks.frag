//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it

//Note that most of this shader's behavior comes from assets/voxels/common.shader.

void main() {
    InData IN = unpackInputs();

    vec2 surface = texture(u_tex_surface, IN.uv).rg;

    packOutputs(texture(u_tex_albedo, IN.uv).rgb,
                0.0,
                surface.x, surface.y,
                IN.worldNormal);
}