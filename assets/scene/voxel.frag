//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it

in vec3 fIn_worldPos;
in vec2 fIn_uv;
flat in uint fIn_packedFaceAxisDir;

uniform sampler2D u_tex_albedo, u_tex_surface;


//Output into a g-buffer for deferred rendering.
layout (location = 0) out vec4 fOut_colors;
layout (location = 1) out vec2 fOut_surface;
layout (location = 2) out vec3 fOut_normal;


void main() {
    uint faceAxis = fIn_packedFaceAxisDir >> 1,
         bFaceDir = fIn_packedFaceAxisDir & 0x1;
    int faceDir = int(bFaceDir * 2) - 1;

    fOut_colors = vec4(texture(u_tex_albedo, fIn_uv).rgb,
                       0.0);
    fOut_surface = texture(u_tex_surface, fIn_uv).rg * vec2(1, 0.3);

    vec3 worldNormal = vec3(0, 0, 0);
    worldNormal[faceAxis] = faceDir;
    fOut_normal = worldNormal;
}