//This program is for a voxel layer that hasn't been meshed yet.
//It dynamically decides in the geometry shader whether each face of each voxel should be rendered,
//    which is obviously slower but requires no pre-processing.

uniform uvec3 u_nVoxels;

out ivec3 gIn_voxelIdx; //Signed is more convenient for the geometry shader.

void main() {
    //Convert from primitive index to voxel grid cell.
    ivec3 nVoxels = ivec3(u_nVoxels);
    gIn_voxelIdx = ivec3(
        gl_VertexID % nVoxels.x,
        (gl_VertexID / u_nVoxels.x) % nVoxels.y,
        gl_VertexID / (nVoxels.x * nVoxels.y)
    );
}