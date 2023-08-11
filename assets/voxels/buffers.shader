//Automatically inserted into every shader.

layout(std140, binding=2) uniform CamBlock {
    vec4 pos;
    vec4 forward;
    vec4 upward;
    vec4 rightward;

    mat4 matView;
    mat4 matProjection;
    mat4 matViewProj;
    mat4 matInvViewProj;

    float nearClip;
    float farClip;
} u_cam;