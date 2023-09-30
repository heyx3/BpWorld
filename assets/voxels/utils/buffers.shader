//Automatically inserted into every shader.

layout(std140, binding=0) uniform FogBlock {
    float density;
    float dropoff;
    float heightOffset;
    float heightScale;
    vec4 color;
} u_fog;

layout(std140, binding=1) uniform LightBlock {
    vec4 dir;
    vec4 emission;
    sampler2DShadow shadowmap;
    float shadowBias;
    mat4 worldToTexelMat;
} u_sun;

layout(std140, binding=2) uniform CamBlock {
    vec4 pos;
    vec4 forward;
    vec4 upward;
    vec4 rightward;

    float nearClip;
    float farClip;

    mat4 matView;
    mat4 matProjection;
    mat4 matViewProj;
    mat4 matInvViewProj;
} u_cam;