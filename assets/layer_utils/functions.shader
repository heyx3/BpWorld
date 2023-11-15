//Automatically inserted into every shader.

// Mostly taken from the following shaders:
//    https://www.shadertoy.com/view/7stBDH

#define PI (3.1415926535897932384626433832795)
#define PI2 (PI * 2.0)

#define OSCILLATE(a, b, input) (mix(a, b, 0.5 + (0.5 * sin(PI2 * (input)))))

#define INV_LERP(a, b, x) ((x-a) / (b-a))
#define SATURATE(x) clamp(x, 0.0, 1.0)
#define SHARPEN(t) smoothstep(0.0, 1.0, t)
#define SHARPENER(t) SMOOTHERSTEP(t)

//Converts a 0-1 value to the (-1, +1) range.
#define NORMALIZED_TO_SIGNED(uv) (-1.0 + (2.0 * uv))
//Converts a (-1, +1) range value to the 0-1 range.
#define SIGNED_TO_NORMALIZED(normal) (0.5 + (0.5 * normal))

//To prevent a comma from being noticed by a macro invocation.
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
//Some noise is defined with the help of macros to work with any-dimensional data.
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
float angleT(vec2 dir) { return 0.5 + (0.5 * atan(dir.y, dir.x)/PI); }

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
    float theta = uniformRandom * PI2;
    return vec2(cos(theta), sin(theta));
}

float linearizedDepth(float renderedDepth, float zNear, float zFar)
{
    //Reference: https://stackoverflow.com/questions/51108596/linearize-depth

    //OpenGL depth is from -1 to +1, but coming from the texture it'll be 0 to 1.
    float z = -1.0 + (2.0 * renderedDepth);
    return (2.0 * zNear * zFar) / ((zFar + zNear) - (z * (zFar - zNear)));
}

//Applies a world matrix (i.e. nothing weird like projection/skew) to a direction,
//    ignoring the translation component.
vec3 transformDir(vec3 dir, mat4 transform)
{
    return (transform * vec4(dir, 0.0)).xyz;
}

//Recreates world-space position from a fragment's depth, given some world-space data.
//Also returns the distance between the camera and fragment, in the W channel.
vec4 positionFromDepth(mat4 projectionMatrix,
                       vec3 camPos, vec3 camForward,
                       vec3 normalizedDirToFragment,
                       float bufferDepth)
{
    //Reference: https://mynameismjp.wordpress.com/2010/09/05/position-from-depth-3/
    //           https://cs.gmu.edu/~jchen/cs662/fog.pdf

    float rawDepth = -1.0 + (2.0 * bufferDepth);
    float viewZ = projectionMatrix[3][2] / (rawDepth + projectionMatrix[2][2]);
    float distToCam = viewZ / dot(normalizedDirToFragment, camForward);
    return vec4((normalizedDirToFragment * distToCam) - camPos, distToCam);
}