//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it


//You may customize this file by #defining things and then including it.

// #define QUAD_TRANSFORM 1 to allow a 3x3 matrix transform on the vertices before rendering.
#ifndef QUAD_TRANSFORM 
    #define QUAD_TRANSFORM 0
#endif
#if QUAD_TRANSFORM == 1
    uniform mat3 u_transform = mat3(1, 0, 0,
                                    0, 1, 0,
                                    0, 0, 1);
#endif

// #define Z_DEPTH 0.0 to set the Z position of the quad to 0.0
//    (or other values as desired).
//By default, it's 0.5.
#ifndef Z_DEPTH
    #define Z_DEPTH 0.5
#endif

// Expects to use the full-screen triangle in 'CResources',
//    or the quad which is very similar.
in vec2 vIn_corner;

out vec2 fIn_uv;

void main() {
    fIn_uv = 0.5 + (0.5 * vIn_corner);

    vec2 pos;
    #if QUAD_TRANSFORM
        vec3 pos3 = u_mesh_transform * vec3(vIn_corner, 1.0);
        pos = pos3.xy / pos3.z;
    #else
        pos = vIn_corner;
    #endif
    gl_Position = vec4(pos, Z_DEPTH, 1.0);
}