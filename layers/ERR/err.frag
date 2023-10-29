void main() {
    InData IN = start();

    //Generate a screen-space checkerboard pattern.
    ivec2 pixel = ivec2(gl_FragCoord);
    bvec2 componentMask = greaterThan(pixel % 7, ivec2(0));
    int patternMask = (int(componentMask.x) + int(componentMask.y)) % 2;

    #if defined(PASS_FORWARD)
        //Derive surface properties from the pattern.
        vec3 albedo = mix(vec3(0), vec3(1, 0, 1), patternMask==1);
        float metallic = 0.1,
              roughness = mix(0.3, 0.865, patternMask==1);

        finish(
            // Albedo, Emissive
            albedo, vec3(0, 0, 0),
            // Metallic, Roughness
            metallic, roughness,
            // Tangent-space Normal
            vec3(0, 0, 1),
            //Surface data
            IN
        );

    #elif defined(PASS_DEPTH)
        //Nothing to output.
        finish();

    #else
        #error What pass is this??

    #endif
}

void main() {
    InData IN = start();
}