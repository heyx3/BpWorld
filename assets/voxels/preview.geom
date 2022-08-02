//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it

//This program is for a voxel layer that hasn't been meshed yet.
//It dynamically decides in the geometry shader whether each face of each voxel should be rendered,
//    which is obviously slower but requires no pre-processing.
//It will use the same fragment shader as the other program for meshed voxels.

#include <voxels/vert_processing.shader>

layout (points) in;
in ivec3 gIn_voxelIdx[];

uniform usampler3D u_voxelGrid;
uniform uint u_voxelLayer;

//Calculates the same fragment shader inputs as the fully-meshed voxel shader.
layout (triangle_strip, max_vertices=24) out;
out vec3 fIn_worldPos;
out vec3 fIn_voxelPos;
out vec2 fIn_uv;
out uint fIn_packedFaceAxisDir;

void main() {
    if (texelFetch(u_voxelGrid, gIn_voxelIdx[0], 0).r != u_voxelLayer)
        return;
    ivec3 texSize = textureSize(u_voxelGrid, 0);

    for (int axis = 0; axis < 3; ++axis)
    {
        ivec2 otherAxesChoices[3] = {
            ivec2(1, 2),
            ivec2(0, 2),
            ivec2(0, 1)
        };
        ivec2 otherAxes = otherAxesChoices[axis];

        for (uint bDir = 0; bDir < 2; ++bDir)
        {
            int dir = (int(bDir) * 2) - 1;

            //Get the neighbor on this face.
            ivec3 neighborPos = gIn_voxelIdx[0];
            neighborPos[axis] += dir;
            //If the neighbor is past the edge of the voxel grid, assume it's empty space.
            uint neighborVoxel = 0;
            if (neighborPos[axis] >= 0 && neighborPos[axis] < texSize[axis])
                neighborVoxel = texelFetch(u_voxelGrid, neighborPos, 0).r;

            //If the neighbor is empty, then this face of our voxel should be rendered.
            if (neighborVoxel == 0)
            {
                fIn_packedFaceAxisDir = packFaceData(axis, dir);

                //Compute the 4 corners of this face,
                //    and emit a triangle strip for them.
                vec3 minCorner = vec3(gIn_voxelIdx[0]);
                const vec2 cornerFaceOffsets[4] = {
                    vec2(0, 0),
                    vec2(1, 0),
                    vec2(0, 1),
                    vec2(1, 1)
                };
                for (int cornerI = 0; cornerI < 4; ++cornerI)
                {
                    vec3 corner = minCorner;
                    corner[axis] += bDir;
                    corner[otherAxes.x] += cornerFaceOffsets[cornerI].x;
                    corner[otherAxes.y] += cornerFaceOffsets[cornerI].y;

                    ProcessedVert gOut = processVertex(corner, axis);
                    fIn_worldPos = gOut.worldPos;
                    fIn_voxelPos = gOut.voxelPos;
                    fIn_uv = gOut.uv;
                    gl_Position = gOut.ndcPos;
                    //Note that fIn_packedFaceAxisDir was set above.
                    EmitVertex();
                }
                EndPrimitive();
            }
        }
    }
}