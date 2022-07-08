//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it

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

//Transforms the voxels from their grid space into world space,
//    then from there into window-space.
//No world-space rotation is allowed, to simplify normals calculation.
uniform vec3 u_offset, u_scale;
uniform mat4 u_mat_viewproj;

out vec3 fIn_worldPos;
out vec2 fIn_uv;
out uint fIn_packedFaceAxisDir;

void main() {
    UnpackedVertexInput vIn = unpackInput(vIn_packedInput);

    fIn_packedFaceAxisDir = (vIn.faceAxis << 1) | vIn.bFaceDir;

    //Compute position in voxel grid space.
    vec3 gridPos = vec3(vIn.voxelIdx);
    gridPos[vIn.faceAxis] += (vIn.bFaceDir == 1) ? 1.0 : 0.0;

    //Compute world and NDC position.
    vec3 worldPos = u_offset + (u_scale * gridPos);
    gl_Position = u_mat_viewproj * vec4(worldPos, 1);
    fIn_worldPos = worldPos;

    // Calculate world-space UV's (or more accurately, grid-space)
    //    based on which axis this face is perpendicular to.
    uvec2 uv_indices[3] = { ivec2(1, 2), ivec2(0, 2), ivec2(0, 1) };
    uvec2 uv_idx = uv_indices[vIn.faceAxis];
    fIn_uv = vec2(gridPos[uv_idx.x], gridPos[uv_idx.y]);
}