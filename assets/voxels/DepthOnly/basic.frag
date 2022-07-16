//Tell the IDE/linter about stuff that the julia program normally injects.
//Otherwise you'll get red squiggles below.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it before compiling

//For depth-only render passes, no color/normal/surface data needs to be output.
//This file is the default fragment shader for voxels during such a pass.

void main() {
    InData IN = unpackInputs();

    //No outputs are necessary.
}