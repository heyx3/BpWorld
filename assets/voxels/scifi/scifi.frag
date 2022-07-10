//Tell the IDE/linter about stuff that the julia program normally injects.
//Otherwise you'll get red squiggles below.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it before compiling

//The project automatically includes "assets/voxels/common.shader",
//    and defines the textures declared in the accompanying "scifi.json" file.

//Expects some parameters to be defined from the JSON.
#ifndef GRADIENT_A
      #error "You didn't #define a GRADIENT_A (should be a vec3)"
#endif
#ifndef GRADIENT_B
      #error "You didn't #define a GRADIENT_B (should be a vec3)"
#endif


void main() {
    InData IN = unpackInputs();

    float map = texture(u_tex_map, IN.uv).r;

    vec3 albedo = mix(GRADIENT_A, GRADIENT_B, map);
    float metallic = 0.85;
    float roughness = mix(0.3, 0.9, map);

    float emissiveScale = pow(map, 10.0) * 10.0;

    packOutputs(albedo, 0.0,
                metallic, roughness,
                IN.worldNormal);
}