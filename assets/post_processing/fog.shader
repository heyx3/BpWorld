
struct Fog
{
    float density;
    float dropoff;
    vec3 color;
    float heightOffset, heightScale;
};

vec3 computeFoggedColor(Fog fog, float camHeight,
                        float fragWorldHeight,
                        float fragDist3D, float fragDistVertical,
                        vec3 surfaceColor)
{
    //Height-fog density is only a function of vertical position.
    //As long as that function can be integrated analytically,
    //    then total fog density itself can be integrated analytically.

    //Using a function of 'f(z) = exp(z)', the integral is 'if(z) = exp(z) + C'.
    //The C cancels out in the definite integral, which is "if(z1) - if(z2)".

    float fogStartHeight = fog.heightScale * (camHeight - fog.heightOffset),
          fogEndHeight = fog.heightScale * (fragWorldHeight - fog.heightOffset),
          fogIntegralScale = (fragDist3D / max(0.00001, fragDistVertical)),
          fogDensityIntegral = abs(fogIntegralScale * (exp(-fogEndHeight) - exp(-fogStartHeight)));

    float fogThickness = SATURATE(fog.density * fogDensityIntegral);
    fogThickness = pow(fogThickness, fog.dropoff);

    return mix(surfaceColor, fog.color, fogThickness);
}