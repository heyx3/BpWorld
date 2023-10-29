void main() {
    InData IN = start();

    #if defined(PASS_FORWARD)
        vec3 albedo = texture(u_tex_albedo, IN.uv).rgb;

        vec2 surface = texture(u_tex_surface, IN.uv).rg;
        float metallic = surface.x,
              roughness = mix(0.3, 1.0, pow(surface.y, 0.5));

        vec3 normal = NORMALIZED_TO_SIGNED(texture(u_tex_normal, IN.uv).rgb);

        finish(
            albedo, vec3(0, 0, 0),
            metallic, roughness,
            normal,
            IN
        );

    #elif defined(PASS_DEPTH)
        //Nothing to output.
        finish();

    #else
        #error What pass are we in??

    #endif
}