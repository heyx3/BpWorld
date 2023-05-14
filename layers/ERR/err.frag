void main() {
    InData IN = unpackInputs();

    //Generate a screen-space checkerboard pattern.
    ivec2 pixel = ivec2(gl_FragCoord);
    bvec2 componentMask = greaterThan(pixel % 7, ivec2(0));
    int patternMask = (int(componentMask.x) + int(componentMask.y)) % 2;

    #if defined(PASS_DEFERRED)
        //Derive surface properties from the pattern.
        vec3 albedo = mix(vec3(0), vec3(1, 0, 1), patternMask==1);
        float metallic = 0.1,
              roughness = mix(0.3, 0.865, patternMask==1);

        packOutputs(albedo, 0.0,
                    metallic, roughness,
                    IN.worldNormal);

    #elif defined(PASS_DEPTH)
        //Do nothing

    #else
        #error What pass is this??

    #endif
}