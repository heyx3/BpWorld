//This program is for a voxel layer that has been meshed.
//The data comes in all pre-processed and packed tightly.

in uvec3 vIn_packedInput;
struct UnpackedVertexInput
{
    uvec3 voxelIdx;
    uint faceAxis;
    uint bFaceDir; //0 for -1, 1 for +1
    int faceDir;// -1 or +1
};
UnpackedVertexInput unpackInput(uvec3 vIn)
{
    uint faceAxis = (vIn.x >> 31) |
                    ((vIn.y >> 31) << 1);
    uint bFaceDir = vIn.z >> 31;

    uvec3 voxelIdx = vIn & 0x7FffFFff;

    return UnpackedVertexInput(voxelIdx, faceAxis, bFaceDir,
                               int(bFaceDir * 2) - 1);
}

#include <../assets/voxels/vert_geom/vert_processing.shader>


out vec3 fIn_worldPos;
out vec3 fIn_voxelPos;
out vec2 fIn_uv;
out uint fIn_packedFaceAxisDir;

void main() {
    UnpackedVertexInput vIn = unpackInput(vIn_packedInput);

    fIn_packedFaceAxisDir = packFaceData(vIn.faceAxis, vIn.faceDir);

    ProcessedVert vOut = processVertex(vIn.voxelIdx, vIn.faceAxis);
    fIn_worldPos = vOut.worldPos;
    fIn_voxelPos = vOut.voxelPos;
    fIn_uv = vOut.uv;
    gl_Position = vOut.ndcPos;
}