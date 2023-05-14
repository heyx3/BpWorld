//Defines the outputs for the G-buffer pass.
//Automatically *conditionally* included in fragment shaders.

#define PASS_DEFERRED 1

layout (location = 0) out vec4 fOut_colors; //RGB=albedo, A=emissive multiplieer
layout (location = 1) out vec2 fOut_surface; //R=metallic, G=roughness
layout (location = 2) out vec3 fOut_normal; //RGB=signed normal

void packOutputs(vec3 albedo, float emissiveScale,
                 float metallic, float roughness,
                 vec3 normal)
{
    fOut_colors = vec4(albedo, emissiveScale);
    fOut_surface = vec2(metallic, roughness);
    fOut_normal = normal;
}