//This file contains common code between the two versions of a voxel's shader:
//    the one before meshing is finished, and the one after meshing is finished.
//The pre-meshing one uses a slower geometry-shader technique
//    while waiting for meshing to complete.


//Transforms the voxels from their grid space into world space,
//    then from there into window-space.
//No world-space rotation is allowed, to simplify normals calculation.
uniform vec3 u_world_offset, u_world_scale;
uniform mat4 u_mat_viewproj;

//Packs a 0-3 axis value and -1/+1 direction value into the first 3 bits of a uint.
uint packFaceData(uint axis, int dir)
{
    uint bFaceDir = uint((dir + 1) / 2);
    return (axis << 1) | bFaceDir;
}

//Compute fragment shader inputs for a given vertex.
struct ProcessedVert
{
    vec3 voxelPos, worldPos;
    vec4 ndcPos;
    vec2 uv;
};
ProcessedVert processVertex(vec3 gridPos, uint axis)
{
    //Compute world and NDC position.
    vec3 worldPos = u_world_offset + (u_world_scale * gridPos);
    vec4 ndcPos = u_mat_viewproj * vec4(worldPos, 1);

    // Calculate grid-space UV's
    //    based on which axis this face is perpendicular to.
    uvec2 uv_indices[3] = { ivec2(1, 2), ivec2(0, 2), ivec2(0, 1) };
    uvec2 uv_idx = uv_indices[axis];
    vec2 uv = vec2(gridPos[uv_idx.x], gridPos[uv_idx.y]);

    return ProcessedVert(
        gridPos, worldPos,
        ndcPos, uv
    );
}