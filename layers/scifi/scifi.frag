//Expects some parameters to be defined from the JSON.
#ifndef GRADIENT_A
      #error You didn't #define a GRADIENT_A (should be a vec3)
#endif
#ifndef GRADIENT_B
      #error You didn't #define a GRADIENT_B (should be a vec3)
#endif


void main() {
    InData IN = unpackInputs();

    #if defined(PASS_DEFERRED)
        float map = texture(u_tex_map, IN.uv).r;

        vec3 albedo = mix(GRADIENT_A, GRADIENT_B, map);
        float metallic = 0.85;
        float roughness = mix(0.3, 0.9, map);

        float emissiveScale = pow(map, 10.0) * 10.0;

        packOutputs(albedo, 0.0,
                    metallic, roughness,
                    IN.worldNormal);

    #elif defined(PASS_DEPTH)
        //Nothing to output.

    #else
        #error What pass are we in??

    #endif
}