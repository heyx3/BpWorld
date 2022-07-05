//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it

//This vertex sits at the min corner of some voxel.
in ivec3 vIn_voxelIdx;
//This vertex is part of a plane pointing perpendicular to an axis.
//This value uses 2 bits for the axis this face is perpendicular to,
//    and one bit for the direction it's facing. 
in uint vIn_faceAxisDir;

//Transforms the voxels from their grid space into world space,
//    then from there into window-space.
uniform mat4 u_mat_world, u_mat_viewproj;

out vec3 fIn_worldPos;
out vec2 fIn_uv;
out uint fIn_faceAxisDir;

void main() {
    //Compute face/axis data.
    fIn_faceAxisDir = vIn_faceAxisDir;
    uint faceAxis = vIn_faceAxisDir & 0x3;
    uint bFaceDir = vIn_faceAxisDir >> 2; // 0 for '-1', 1 for '+1'
    int faceDir = int(bFaceDir * 2) - 1;

    //Compute position in voxel grid space.
    vec3 gridPos = vec3(vIn_voxelIdx);

    //Compute world and NDC position.
    vec4 worldPos4 = u_mat_world * vec4(gridPos, 1);
    gl_Position = u_mat_viewproj * worldPos4;
    fIn_worldPos = worldPos4.xyz / worldPos4.w;

    // Calculate world-space UV's (or more accurately, grid-space)
    //    based on which axis this face is perpendicular to.
    ivec2 uv_indices[3] = { ivec2(1, 2), ivec2(0, 2), ivec2(0, 1) };
    ivec2 uv_idx = uv_indices[faceAxis];
    fIn_uv = vec2(gridPos[uv_idx.x], gridPos[uv_idx.y]);
}