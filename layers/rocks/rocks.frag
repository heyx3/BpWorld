void main() {
    InData IN = unpackInputs();

    #if defined(PASS_DEFERRED)
        vec2 surface = texture(u_tex_surface, IN.uv).rg;
        float metallic = surface.x,
              roughness = mix(0.3, 1.0, pow(surface.y, 0.5));

        //TODO: incorporate "u_tex_normal"

        packOutputs(texture(u_tex_albedo, IN.uv).rgb,
                    0.0,
                    metallic, roughness,
                    IN.worldNormal);

    #elif defined(PASS_DEPTH)
        //Nothing to output.

    #else
        #error What pass are we in??

    #endif
}