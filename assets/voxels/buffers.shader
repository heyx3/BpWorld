//Automatically inserted into every shader.

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