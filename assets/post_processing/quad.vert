//You may customize this file by #defining things before including it.

// '#define QUAD_TRANSFORM 1' to allow a 3x3 matrix transform on the vertices before rendering.
#ifndef QUAD_TRANSFORM 
    #define QUAD_TRANSFORM 0
#endif
#if QUAD_TRANSFORM == 1
    uniform mat3 u_transform = mat3(1, 0, 0,
                                    0, 1, 0,
                                    0, 0, 1);
#endif

// '#define Z_DEPTH 0.0' to set the Z position of the quad to 0.0
//    (or other values as desired).
//By default, it's 0.5.
#ifndef Z_DEPTH
    #define Z_DEPTH 0.5
#endif

// '#define FRAGMENT_DIR 1' to add a new fragment shader input
//    representing a vector from the camera towards that fragment.
//The space of that fragment is up to you; set the uniform "u_mat_dirProjection"
//    to map from projection space to view- or world-space;
//    and set "u_camPosForDir" to the camera's position in that space.
#ifndef FRAGMENT_DIR
    #define FRAGMENT_DIR 0
#endif
#if FRAGMENT_DIR == 1
    out vec3 fIn_camToFragment;
    uniform mat4 u_mat_dirProjection;
    uniform vec3 u_camPosForDir;
#endif


// Expects to use the full-screen triangle in 'CResources',
//    or the quad which is very similar.
//The values are (effectively) in the range -1, +1.
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
    vec3 posNDC = vec3(pos, Z_DEPTH);
    gl_Position = vec4(posNDC, 1.0);

    #if FRAGMENT_DIR
        vec4 fragmentPos4 = u_mat_dirProjection * vec4(posNDC, 1);
        vec3 fragmentPos = fragmentPos4.xyz / fragmentPos4.w;
        fIn_camToFragment = (fragmentPos - u_camPosForDir);
    #endif
}