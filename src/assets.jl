const ASSETS_FOLDER = joinpath(@__DIR__, "..", "assets")
macro bp_asset_str(str::AbstractString)
    return joinpath(ASSETS_FOLDER, str)
end


const SHADER_COMMON = begin # Nested to make it collapsible
    # Mostly taken from the following shaders:
    #    https://www.shadertoy.com/view/7stBDH
    """
    ////////////////////
    //    Hashing     //
    ////////////////////

    // A modified version of this: https://www.shadertoy.com/view/4djSRW
    //Works best with seed values in the hundreds.

    //Hash 1D from 1D-3D data
    float hashTo1(float p)
    {
        p = fract(p * .1031);
        p *= p + 33.33;
        p *= p + p;
        return fract(p);
    }
    float hashTo1(vec2 p)
    {
        vec3 p3  = fract(vec3(p.xyx) * .1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }
    float hashTo1(vec3 p3)
    {
        p3  = fract(p3 * .1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
    }

    //Hash 2D from 1D-3D data
    vec2 hashTo2(float p)
    {
        vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.xx+p3.yz)*p3.zy);

    }
    vec2 hashTo2(vec2 p)
    {
        vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx+33.33);
        return fract((p3.xx+p3.yz)*p3.zy);

    }
    vec2 hashTo2(vec3 p3)
    {
        p3 = fract(p3 * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yzx+33.33);
        return fract((p3.xx+p3.yz)*p3.zy);
    }

    //Hash 3D from 1D-3D data
    vec3 hashTo3(float p)
    {
    vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xxy+p3.yzz)*p3.zyx); 
    }
    vec3 hashTo3(vec2 p)
    {
        vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yxz+33.33);
        return fract((p3.xxy+p3.yzz)*p3.zyx);
    }
    vec3 hashTo3(vec3 p3)
    {
        p3 = fract(p3 * vec3(.1031, .1030, .0973));
        p3 += dot(p3, p3.yxz+33.33);
        return fract((p3.xxy + p3.yxx)*p3.zyx);
    }

    //Hash 4D from 1D-4D data
    vec4 hashTo4(float p)
    {
        vec4 p4 = fract(vec4(p) * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
        
    }
    vec4 hashTo4(vec2 p)
    {
        vec4 p4 = fract(vec4(p.xyxy) * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);

    }
    vec4 hashTo4(vec3 p)
    {
        vec4 p4 = fract(vec4(p.xyzx)  * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    }
    vec4 hashTo4(vec4 p4)
    {
        p4 = fract(p4  * vec4(.1031, .1030, .0973, .1099));
        p4 += dot(p4, p4.wzxy+33.33);
        return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    }



    //////////////////////
    //    Utilities     //
    //////////////////////

    #define OSCILLATE(a, b, input) (mix(a, b, 0.5 + (0.5 * sin(2.0 * 3.14159265 * (input)))))

    #define INV_LERP(a, b, x) ((x-a) / (b-a))
    #define SATURATE(x) clamp(x, 0.0, 1.0)
    #define SHARPEN(t) smoothstep(0.0, 1.0, t)
    #define SHARPENER(t) SMOOTHERSTEP(t)

    #define COMMA ,

    #define RAND_IN_ARRAY(array, t) array[int(mix(0.0, float(array.length()) - 0.00001, t))]

    //A higher-quality smoothstep(), with a zero second-derivative at the edges.
    #define SMOOTHERSTEP(t) clamp(t * t * t * (t * (t*6.0 - 15.0) + 10.0), \
                                0.0, 1.0)

    //Returns a value that increases towards 1 as it gets closer to some target.
    float border(float x, float target, float thickness, float dropoff)
    {
        float dist = abs(x - target);
        float closeness = 1.0 - min(1.0, dist / thickness);
        return pow(closeness, dropoff);
    }

    //Distance-squared is faster to compute in 2D+, but not in 1D.
    //Some noise is defined with the help of macros to work with any dimensionality,
    //    and so is agnostic to the dimensionality.
    float efficientDist(float a, float b) { return abs(b - a); }
    float efficientDist(vec2 a, vec2 b) { vec2 delta = b - a; return dot(delta, delta); }
    float efficientDist(vec3 a, vec3 b) { vec3 delta = b - a; return dot(delta, delta); }
    float efficientDist(vec4 a, vec4 b) { vec4 delta = b - a; return dot(delta, delta); }
    float realDist(float efficientDist, float posType) { return efficientDist; }
    float realDist(float efficientDist, vec2 posType) { return sqrt(efficientDist); }
    float realDist(float efficientDist, vec3 posType) { return sqrt(efficientDist); }
    float realDist(float efficientDist, vec4 posType) { return sqrt(efficientDist); }

    float sumComponents(float f) { return f; }
    float sumComponents(vec2 v) { return v.x + v.y; }
    float sumComponents(vec3 v) { return v.x + v.y + v.z; }
    float sumComponents(vec4 v) { return v.x + v.y + v.z + v.w; }

    //Gets the angle of the given vector, in the range 0-1.
    float angleT(vec2 dir) { return 0.5 + (0.5 * atan(dir.y, dir.x)/3.14159265); }

    //Given a uniformly-distributed value, and another target value,
    //    biases the uniform value towards the target.
    //The "biasStrength" should be between 0 and 1.
    float applyBias(float x, float target, float biasStrength)
    {
        //Degenerative case if x=0.
        if (x == 0.0)
            return mix(x, target, biasStrength);
        
        //Get the "scale" of the target relative to x.
        //Multiplying x by this number would give exactly the target.
        float scale = target / x;
        
        //Weaken the "scale" by pushing it towards 1.0, then apply it to 'x'.
        //Make sure to respect the sign, in case 'x' or 'target' is negative.
        return x * sign(scale) * pow(abs(scale), biasStrength);
    }

    //Linearly interpolates between a beginning, midpoint, and endpoint.
    float tripleLerp(float a, float b, float c, float t)
    {
        vec3 lerpArgs = (t < 0.5) ?
                            vec3(a, b, INV_LERP(0.0, 0.5, t)) :
                            vec3(b, c, INV_LERP(0.5, 1.0, t));
        return mix(lerpArgs.x, lerpArgs.y, lerpArgs.z);
    }
    vec3 tripleLerp(vec3 a, vec3 b, vec3 c, float t)
    {
        bool isFirstHalf = (t < 0.5);
        return isFirstHalf ?
                mix(a, b, INV_LERP(0.0, 0.5, t)) :
                mix(b, c, INV_LERP(0.5, 1.0, t));
        
    }
    //Smoothly interpolates between a beginning, midpoint, and endpoint.
    float tripleSmoothstep(float a, float b, float c, float t)
    {
        vec4 lerpArgs = (t < 0.5) ?
                            vec4(a, b, 0.0, 0.5) :
                            vec4(b, c, 0.5, 1.0);
        return mix(lerpArgs.x, lerpArgs.y, smoothstep(lerpArgs.z, lerpArgs.w, t));
    }
    //Interpolates between a beginning, midpoint, and endpoint, with aggressive smoothing.
    float tripleSmoothSmoothstep(float a, float b, float c, float t)
    {
        vec4 lerpArgs = (t < 0.5) ?
                            vec4(a, b, 0.0, 0.5) :
                            vec4(b, c, 0.5, 1.0);
        return mix(lerpArgs.x, lerpArgs.y, smoothstep(0.0, 1.0, smoothstep(lerpArgs.z, lerpArgs.w, t)));
    }

    vec2 randUnitVector(float uniformRandom)
    {
        float theta = uniformRandom * 2.0 * 3.14159265;
        return vec2(cos(theta), sin(theta));
    }

    ///////////////////////////////
    //    Value/Octave Noise     //
    ///////////////////////////////

    float valueNoise(float x, float seed)
    {
        float xMin = floor(x),
            xMax = ceil(x);

        float noiseMin = hashTo1(vec2(xMin, seed) * 450.0),
            noiseMax = hashTo1(vec2(xMax, seed) * 450.0);

        float t = x - xMin;
        //t = SMOOTHERSTEP(t); //Actually gives worse results due to
                            //  the dumb simplicity of the underlying noise
        
        return mix(noiseMin, noiseMax, t);
    }
    float valueNoise(vec2 x, float seed)
    {
        vec2 xMin = floor(x),
            xMax = ceil(x);
        vec4 xMinMax = vec4(xMin, xMax);

        vec2 t = x - xMin;
        //t = SMOOTHERSTEP(t); //Actually gives worse results due to
                            //  the dumb simplicity of the underlying noise
        
        #define VALUE_NOISE_2D(pos) hashTo1(vec3(pos, seed) * 450.0)
        return mix(mix(VALUE_NOISE_2D(xMinMax.xy),
                    VALUE_NOISE_2D(xMinMax.zy),
                    t.x),
                mix(VALUE_NOISE_2D(xMinMax.xw),
                    VALUE_NOISE_2D(xMinMax.zw),
                    t.x),
                t.y);
    }

    //Octave noise behaves the same regardless of dimension.
    #define IMPL_OCTAVE_NOISE(x, outputVar, persistence, seed, nOctaves, noiseFunc, noiseMidArg, octaveValueMod) \
        float outputVar; { \
        float sum = 0.0,                                                 \
            scale = 1.0,                                               \
            nextWeight = 1.0,                                          \
            totalWeight = 0.0;                                         \
        for (int i = 0; i < nOctaves; ++i)                               \
        {                                                                \
            float octaveValue = noiseFunc((x) * scale,                   \
                                        noiseMidArg                    \
                                        (seed) + float(i));            \
            octaveValueMod;                                              \
            sum += octaveValue * nextWeight;                             \
            totalWeight += nextWeight;                                   \
                                                                        \
            nextWeight /= (persistence);                                 \
            scale *= (persistence);                                      \
        }                                                                \
        outputVar = sum / totalWeight;                                   \
    }
    float octaveNoise(float x, float seed, int nOctaves, float persistence) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, valueNoise, ,); return outNoise; }
    float octaveNoise(vec2 x, float seed, int nOctaves, float persistence) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, valueNoise, ,); return outNoise; }

    #define PERLIN_MAX(nDimensions) (sqrt(float(nDimensions)) / 2.0)
    float perlinNoise(float x, float seed)
    {
        float xMin = floor(x),
            xMax = ceil(x),
            t = x - xMin;

        float value = mix(t         * sign(hashTo1(vec2(xMin, seed) * 450.0) - 0.5),
                        (1.0 - t) * sign(hashTo1(vec2(xMax, seed) * 450.0) - 0.5),
                        SHARPENER(t));
        return INV_LERP(-PERLIN_MAX(1), PERLIN_MAX(1), value);
    }

    vec2 perlinGradient2(float t)
    {
        return randUnitVector(t);
    }
    float perlinNoise(vec2 p, float seed)
    {
        vec2 pMin = floor(p),
            pMax = pMin + 1.0,
            t = p - pMin;
        vec4 pMinMax = vec4(pMin, pMax),
            tMinMax = vec4(t, p - pMax);

        #define PERLIN2_POINT(ab) dot(tMinMax.ab, \
                                    perlinGradient2(hashTo1(vec3(pMinMax.ab, seed) * 450.0)))
        float noiseMinXMinY = PERLIN2_POINT(xy),
            noiseMaxXMinY = PERLIN2_POINT(zy),
            noiseMinXMaxY = PERLIN2_POINT(xw),
            noiseMaxXMaxY = PERLIN2_POINT(zw);

        t = SHARPENER(t);
        float value = mix(mix(noiseMinXMinY, noiseMaxXMinY, t.x),
                        mix(noiseMinXMaxY, noiseMaxXMaxY, t.x),
                        t.y);
        return INV_LERP(-PERLIN_MAX(2), PERLIN_MAX(2), value);
    }



    /////////////////////////
    //    Worley Noise     //
    /////////////////////////

    //Helper function for worley noise that finds the point in a cell.
    //Outputs its position, and returns whether or not it really exists.
    bool getWorleyPoint(float cell, float chanceOfPoint, float seed, out float pos)
    {
        vec2 rng = hashTo2(vec2(cell * 450.0, seed)).xy;
        
        pos = cell + rng.x;
        return (rng.y < chanceOfPoint);
    }
    bool getWorleyPoint(vec2 cell, float chanceOfPoint, float seed, out vec2 pos)
    {
        vec3 rng = hashTo3(vec3(cell, seed) * 450.0).xyz;
        
        pos = cell + rng.xy;
        return (rng.z < chanceOfPoint);
    }

    //Generates worley-noise points that might influence the given position.
    //See the below functions for common use-cases.
    void worleyPoints(float x, float chanceOfPoint, float seed,
                    out int outNPoints, out float outPoints[3]);
    void worleyPoints(vec2 x, float chanceOfPoint, float seed,
                    out int outNPoints, out float outPoints[3]);
    //Implementation below:
    #define IMPL_WORLEY_START(T)                                    \
        T xCenter = floor(x),                                       \
        xMin = xCenter - 1.0,                                     \
        xMax = xCenter + 1.0;                                     \
        nPoints = 0;                                                \
        T nextPoint
    //end #define
    #define IMPL_WORLEY_POINT(cellPos)                                  \
        if (getWorleyPoint(cellPos, chanceOfPoint, seed, nextPoint))    \
            points[nPoints++] = nextPoint
    //end #define
    void worleyPoints(float x, float chanceOfPoint, float seed,
                    out int nPoints, out float points[3])
    {
        IMPL_WORLEY_START(float);
        IMPL_WORLEY_POINT(xMin);
        IMPL_WORLEY_POINT(xCenter);
        IMPL_WORLEY_POINT(xMax);
    }
    void worleyPoints(vec2 x, float chanceOfPoint, float seed,
                    out int nPoints, out vec2 points[9])
    {
        IMPL_WORLEY_START(vec2);
        
        IMPL_WORLEY_POINT(xMin);
        IMPL_WORLEY_POINT(xCenter);
        IMPL_WORLEY_POINT(xMax);
        
        IMPL_WORLEY_POINT(vec2(xMin.x, xCenter.y));
        IMPL_WORLEY_POINT(vec2(xMin.x, xMax.y));
        
        IMPL_WORLEY_POINT(vec2(xCenter.x, xMin.y));
        IMPL_WORLEY_POINT(vec2(xCenter.x, xMax.y));
        
        IMPL_WORLEY_POINT(vec2(xMax.x, xMin.y));
        IMPL_WORLEY_POINT(vec2(xMax.x, xCenter.y));
    }

    //Variant 1: straight-line distance, to the nearest point.
    float worley1(float x, float chanceOfPoint, float seed);
    float worley1(vec2 x, float chanceOfPoint, float seed);
    //Implementation below:
    #define IMPL_WORLEY1(T, nMaxPoints)                                              \
    float worley1(T x, float chanceOfPoint, float seed) {                            \
        int nPoints;                                                                 \
        T points[nMaxPoints];                                                        \
        worleyPoints(x, chanceOfPoint, seed, nPoints, points);                       \
                                                                                    \
        if (nPoints < 1)                                                             \
            return 1.0; /* The nearest point is far away */                          \
                                                                                    \
        float minDist = 9999999.9;                                                   \
        for (int i = 0; i < min(nMaxPoints, nPoints); ++i) /*Specify a hard-coded cap,  */            \
        {                                                  /*   in case it helps with unrolling   */  \
            minDist = min(minDist, efficientDist(points[i], x));                     \
        }                                                                            \
        return min(realDist(minDist, points[0]), 1.0);                \
    }
    //end #define
    IMPL_WORLEY1(float, 3)
    IMPL_WORLEY1(vec2,  9)

    //Variant 2: manhattan distance, to the nearest point.
    float worley2(float x, float chanceOfPoint, float seed);
    float worley2(vec2 x, float chanceOfPoint, float seed);
    //Implementation below:
    #define IMPL_WORLEY2(T, nMaxPoints)                                              \
    float worley2(T x, float chanceOfPoint, float seed) {                            \
        int nPoints;                                                                 \
        T points[nMaxPoints];                                                        \
        worleyPoints(x, chanceOfPoint, seed, nPoints, points);                       \
                                                                                    \
        if (nPoints < 1)                                                             \
            return 1.0; /* The nearest point is far away */                          \
                                                                                    \
        float minDist = 9999999.9;                                                   \
        for (int i = 0; i < min(nMaxPoints, nPoints); ++i) /* Specify a hard-coded cap,  */           \
        {                                                  /*   in case it helps with unrolling   */  \
            minDist = min(minDist, sumComponents(abs(points[i] - x)));               \
        }                                                                            \
        return min(realDist(minDist, points[0]), 1.0);                               \
    }
    //end #define
    IMPL_WORLEY2(float, 3)
    IMPL_WORLEY2(vec2,  9)

    //Variant 3: straight-line distance, to the second- nearest point.
    float worley3(float x, float chanceOfPoint, float seed);
    float worley3(vec2 x, float chanceOfPoint, float seed);
    //Implementation below:
    #define IMPL_WORLEY3(T, nMaxPoints)                                              \
    float worley3(T x, float chanceOfPoint, float seed) {                            \
        int nPoints;                                                                 \
        T points[nMaxPoints];                                                        \
        worleyPoints(x, chanceOfPoint, seed, nPoints, points);                       \
                                                                                    \
        if (nPoints < 1)                                                             \
            return 1.0; /* The nearest point is far away */                          \
                                                                                    \
        float minDist1 = 9999999.9,                                                  \
            minDist2 = 9999999.9;                                                  \
        for (int i = 0; i < min(nMaxPoints, nPoints); ++i) /* Specify a hard-coded cap,  */           \
        {                                                  /*   in case it helps with unrolling   */  \
            float newD = efficientDist(points[i], x);                                \
            if (newD < minDist1) {                                                   \
                minDist2 = minDist1; minDist1 = newD;                                \
            } else if (newD < minDist2) {                                            \
                minDist2 = newD;                                                     \
            }                                                                        \
        }                                                                            \
        return SATURATE(min(realDist(minDist2, points[0]) / 1.5, 1.0));                    \
    }
    //end #define
    IMPL_WORLEY3(float, 3)
    IMPL_WORLEY3(vec2,  9)

    //TODO: More variants

    //Octave worley noise:
    float octaveWorley1Noise(float x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley1, chanceOfCell COMMA, ); return outNoise; }
    float octaveWorley1Noise(vec2 x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley1, chanceOfCell COMMA, ); return outNoise; }
    float octaveWorley2Noise(float x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley2, chanceOfCell COMMA, ); return outNoise; }
    float octaveWorley2Noise(vec2 x, float seed, int nOctaves, float persistence, float chanceOfCell) { IMPL_OCTAVE_NOISE(x, outNoise, persistence, seed, nOctaves, worley2, chanceOfCell COMMA, ); return outNoise; }

    //TODO: Profile worley noise compared to a more hard-coded implementation.

    /////////////////////////////////////////////////////////////////
    """
end


mutable struct Assets
    tex_tile::Texture
end
function Base.close(a::Assets)
    for field in fieldnames(typeof(a))
        close(getfield(a, field))
    end
end


function Assets()
    # Tile texture:
    tex_tile_pixels_raw::Matrix = load(bp_asset"Tile.png")
    tex_tile_pixels::Matrix{UInt8} = map(pixel -> reinterpret(pixel.r), tex_tile_pixels_raw)
    (tex_tile_height, tex_tile_width) = size(tex_tile_pixels)
    tex_tile = Texture(
        SimpleFormat(FormatTypes.normalized_uint,
                     SimpleFormatComponents.R,
                     SimpleFormatBitDepths.B8),
        tex_tile_pixels
    )

    return Assets(tex_tile)
end