//Defines the inputs/parameters for every fragment shader.
//Automatically inserted into every fragment shader.

uniform vec3 u_camPos, u_camForward, u_camUp;
uniform float u_totalSeconds;


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