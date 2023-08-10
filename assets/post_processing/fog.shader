
layout(std140, binding=0) uniform FogBlock {
    float density;
    float dropoff;
    float heightOffset;
    float heightScale;
    vec3 color;
} u_fog;

vec3 computeFoggedColor(float camHeight,
                        float fragWorldHeight,
                        float fragDist3D, float fragDistVertical,
                        vec3 surfaceColor)
{
    //Height-fog density is only a function of vertical position.
    //As long as that function can be integrated analytically,
    //    then total fog density itself can be integrated analytically.

    //Using a function of 'f(z) = exp(z)', the integral is 'if(z) = exp(z) + C'.
    //The C cancels out in the definite integral, which is "if(z1) - if(z2)".

    float fogStartHeight = u_fog.heightScale * (camHeight - u_fog.heightOffset),
          fogEndHeight = u_fog.heightScale * (fragWorldHeight - u_fog.heightOffset),
          fogIntegralScale = (fragDist3D / max(0.00001, fragDistVertical)),
          fogDensityIntegral = abs(fogIntegralScale * (exp(-fogEndHeight) - exp(-fogStartHeight)));

    float fogThickness = SATURATE(u_fog.density * fogDensityIntegral);
    fogThickness = pow(fogThickness, u_fog.dropoff);

    return mix(surfaceColor, u_fog.color, fogThickness);
}