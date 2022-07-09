//Tell the IDE/linter about stuff that the julia program normally injects.
//Otherwise you'll get red squiggles below.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it before compiling

//The project automatically includes "assets/voxels/common.shader",
//    and defines the textures declared in the accompanying "rocks.json" file.

void main() {
    InData IN = unpackInputs();

    vec2 surface = texture(u_tex_surface, IN.uv).rg;
    float metallic = surface.x,
          roughness = surface.y * 0.3;

    //TODO: incorporate "u_tex_normal"

    packOutputs(texture(u_tex_albedo, IN.uv).rgb,
                0.0,
                metallic, roughness,
                IN.worldNormal);
}