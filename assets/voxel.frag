//Tell the linter about stuff that the julia program normally injects.
#version 460
#extension GL_GOOGLE_include_directive: require
#extension GL_ARB_bindless_texture : require
#extension GL_ARB_gpu_shader_int64 : require
// #J#J#
//  ^^ Tells the Julia project to cut off everything before it

in vec3 fIn_worldPos;
in vec2 fIn_uv;
flat in uint fIn_faceAxisDir;


uniform float u_specular, u_specularDropoff;
uniform sampler2D u_tex2d_albedo;

uniform vec3 u_camPos, u_camDir;


out vec4 fOut_color;


void main() {
    uint faceAxis = fIn_faceAxisDir & 0x3;
    uint bFaceDir = fIn_faceAxisDir >> 2; // 0 for '-1', 1 for '+1'
    int faceDir = int(bFaceDir * 2) - 1;

    vec3 albedo = texture(u_tex2d_albedo, fIn_uv).rgb;

    vec3 worldNormal = vec3(0, 0, 0);
    worldNormal[faceAxis] = faceDir;

    vec3 camToSurface = fIn_worldPos - u_camPos;
    float surfaceDist = length(camToSurface);
    vec3 camToSurfaceN = camToSurface / surfaceDist;

    //Hard-code some Phong lighting.
    const vec3 sunDir = normalize(vec3(1, 1, -1)),
               sunColor = vec3(1.0, 0.95, 0.9);
    float diffuse = max(0.0, dot(worldNormal, -sunDir)),
          specular = max(0.0, dot(reflect(camToSurfaceN, worldNormal), -sunDir));
    specular = pow(specular * u_specular, u_specularDropoff);
    vec3 litColor = clamp(albedo * diffuse + (sunColor * specular),
                          vec3(0), vec3(1));

    fOut_color = vec4(litColor, 1);
}