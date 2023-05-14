// Mostly taken from the following shaders:
//    https://www.shadertoy.com/view/7stBDH

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