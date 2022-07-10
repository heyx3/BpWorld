// Common code that's needed by voxel fragment shaders.
// Automatically inserted into any voxel fragment shader.

#include <utils.shader>

uniform vec3 u_camPos, u_camForward, u_camUp;
uniform float u_totalSeconds;

//TODO: Other useful uniforms like "elapsed time"


in vec3 fIn_worldPos;
in vec3 fIn_voxelPos;
in vec2 fIn_uv;
flat in uint fIn_packedFaceAxisDir;

struct InData
{
    vec3 worldPos, voxelPos;
    vec3 worldNormal;
    vec2 uv;
    uint faceAxis;

    int faceDir; // -1 or +1
    uint bFaceDir; // 0 or 1
};
InData unpackInputs()
{
    uint faceAxis = fIn_packedFaceAxisDir >> 1,
         bFaceDir = fIn_packedFaceAxisDir & 0x1;
    int faceDir = int(bFaceDir * 2) - 1;

    vec3 worldNormal = vec3(0, 0, 0);
    worldNormal[faceAxis] = faceDir;

    return InData(
        fIn_worldPos, fIn_voxelPos,
        worldNormal,
        fIn_uv,
        faceAxis, faceDir, bFaceDir
    );
}

//Output into a g-buffer for deferred rendering.
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