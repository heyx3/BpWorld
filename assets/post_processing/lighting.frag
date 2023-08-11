//#TODO: Use a compute shader instead

#include <../assets/voxels/utils.shader>
#include <../assets/voxels/buffers.shader>
#include <../assets/post_processing/fog.shader>

struct GBuffer
{
    sampler2D depth, colors, normals, surface;
};
uniform GBuffer u_gBuffer;

layout(std140, binding=1) uniform LightBlock {
    vec4 dir;
    vec4 emission;
    sampler2DShadow shadowmap;
    float shadowBias;
    mat4 worldToTexelMat;
} u_sun;


//BRDF-related equations, using the "micro-facet" model.
//Reference: https://learnopengl.com/PBR/Lighting

//Approximates the light reflected from a surface, given its glancing angle.
vec3 fresnelSchlick(float diffuseStrength, vec3 F0)
{
    return F0 + ((1.0 - F0) * pow(1.0 - diffuseStrength, 5.0));
}
//Approximates the proportion of micro-facets
//    which are facing the right way to reflect light into the camera.
float distributionGGX(float specularStrength, float roughness)
{
    float a      = roughness*roughness,
          a2     = a*a;

    float num   = a2;
    float denom = (specularStrength * specularStrength * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}
//Approximates the proportion of micro-facets which are visible
//    to both the light and the camera.
float geometrySchlickGGX(float diffuseStrength, float roughness)
{
    float num   = diffuseStrength;
    float denom = diffuseStrength * (1.0 - roughness) + roughness;

    return diffuseStrength / ((diffuseStrength * (1.0 - roughness)) + roughness);
}
float geometrySmith(float diffuseNormalAndCamera, float diffuseNormalAndLight,
                    float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;
    return geometrySchlickGGX(diffuseNormalAndCamera, k) *
           geometrySchlickGGX(diffuseNormalAndLight, k);
}

//Implements a microfacet lighting model, using approximations for various factors
//    (see the functions above).
vec3 microfacetLighting(vec3 normal, vec3 towardsCamera, vec3 towardsLight,
                        vec3 lightIrradiance,
                        vec3 albedo, float metallic, float roughness)
{
    //TODO: rename 'idealNormal'
    vec3 halfwayNormal = normalize(towardsLight + towardsCamera);

    float diffuseStrength = SATURATE(dot(normal, towardsLight)),
          specularStrength = SATURATE(dot(halfwayNormal, normal)),
          normalClosenessToCamera = SATURATE(dot(normal, towardsCamera));

    //TODO: Add some sky to the incoming light.
    //TODO: Render sky to hemisphere texture, sample from that for more interesting results

    vec3 F0 = mix(vec3(0.04), albedo, metallic),
         F = fresnelSchlick(SATURATE(dot(halfwayNormal, towardsCamera)), F0);

    vec3 energyOfReflection = F,
         energyOfDiffuse = (1.0 - energyOfReflection) * (1.0 - metallic);

    float NDF = distributionGGX(specularStrength, roughness),
          G = geometrySmith(normalClosenessToCamera, diffuseStrength, roughness);

    vec3 specular = F * (NDF * G / max(0.0001, 4.0 * normalClosenessToCamera * diffuseStrength));
    vec3 totalLight = (((energyOfDiffuse / PI) * albedo) + specular) *
                      lightIrradiance * diffuseStrength;

    return totalLight;
}

vec3 ambientLighting(vec3 surfacePos, vec3 normal, vec3 albedo)
{
    //TODO: More interesting ambient term
    return vec3(0.03) * albedo;
}


//Expects to use the feature 'FRAGMENT_DIR' from the vertex shader,
//    to get the world-space direction towards this fragment.
in vec3 fIn_camToFragment;

in vec2 fIn_uv;

out vec4 fOut_color; //RGB = color (in HDR). A = (0 if sky, 1 otherwise)


void main() {

    //Read and unpack the color texture.
    vec4 colorRead = textureLod(u_gBuffer.colors, fIn_uv, 0.0);
    vec3 albedo = colorRead.rgb,
         emissive = albedo * colorRead.a;

    //Read the depth texture and compute world position.
    float rawDepth = textureLod(u_gBuffer.depth, fIn_uv, 0.0).r;
    vec3 ndcPos = -1.0 + (2.0 * vec3(fIn_uv, rawDepth));
    vec4 worldPos4 = u_cam.matInvViewProj * vec4(ndcPos, 1.0);
    vec3 worldPos = worldPos4.xyz / worldPos4.w;
    vec3 camTowardsPos = worldPos - u_cam.pos.xyz;
    float verticalWorldDist = abs(camTowardsPos.z);
    float worldDist = length(camTowardsPos);
    camTowardsPos /= worldDist;
    vec3 towardsCam = -camTowardsPos;

    //If this pixel is at max depth, assume it's sky.
    if (rawDepth == 1.0)
    {
        vec3 reflectedColor = vec3(0.8, 0.825, 1.0) +
                              pow(max(0.0, dot(u_sun.dir.xyz, -camTowardsPos)),
                                  256.0);
        fOut_color = vec4(reflectedColor, 0);
        return;
    }
    else
    {
        //Output with an alpha of 1 to indicate "solid surface".
        fOut_color.a = 1.0;
    }

    //Try computing world position in the new, fancy way.
    vec3 NEW_camTowardsPos = normalize(fIn_camToFragment);
    vec4 NEW_worldPosData = positionFromDepth(u_cam.matProjection,
                                              u_cam.pos.xyz,
                                              u_cam.forward.xyz,
                                              normalize(fIn_camToFragment),
                                              rawDepth);
    vec3 NEW_worldPos = NEW_worldPosData.xyz;
    float NEW_worldDist = NEW_worldPosData.w;

//DEBUG: optionally use the newer, faster calculation for world-space position.
if (false) { //TODO: Debug this stuff
// fOut_color = vec4(vec3(
//                     distance(NEW_worldDist, worldDist) / 1.0
//                     //fract(worldPos * 0.01)
//                   ), 1);
//fOut_color.rgb = abs(normalize(fIn_camToFragment));
//return;
    worldPos = NEW_worldPos;
    worldDist = NEW_worldDist;
    camTowardsPos = u_cam.pos.xyz - worldPos;
    verticalWorldDist = abs(camTowardsPos.z);
    camTowardsPos /= worldDist;
    towardsCam = -camTowardsPos;
}

    float linearDepth = linearizedDepth(rawDepth, u_cam.nearClip, u_cam.farClip);

    //Read normals.
    vec3 normal = normalize(textureLod(u_gBuffer.normals, fIn_uv, 0.0).rgb);

    //Read and unpack surface data.
    vec2 surfaceRead = textureLod(u_gBuffer.surface, fIn_uv, 0.0).rg;
    float metallic = surfaceRead.r,
          roughness = surfaceRead.g;

    //Compute lighting.
    //Surface model:
    vec3 surfaceLight = microfacetLighting(
        normal, -camTowardsPos, -u_sun.dir.xyz,
        u_sun.emission.rgb,
        albedo, metallic, roughness
    );
    //Shadow-maps:
    vec3 shadowMapWorldPos = worldPos - (u_sun.dir.xyz * u_sun.shadowBias);
    vec4 shadowmapTexel4 = u_sun.worldToTexelMat * vec4(shadowMapWorldPos, 1);
    vec3 shadowmapTexel = shadowmapTexel4.xyz / shadowmapTexel4.w;
    float shadowMask = texture(u_sun.shadowmap, shadowmapTexel).r;
    surfaceLight *= shadowMask;
    //Ambient:
    surfaceLight += ambientLighting(worldPos, normal, albedo);

    //TODO: Emissive

    //Compute height-fog.
    vec3 foggedColor = computeFoggedColor(u_cam.pos.z, worldPos.z,
                                          worldDist, verticalWorldDist,
                                          surfaceLight);

    //Apply tonemapping/gamma-correction.
    vec3 tonedColor = foggedColor / (foggedColor + 1.0);
    tonedColor = pow(tonedColor, vec3(1.0 / 2.2));

    fOut_color.rgb = tonedColor;
}