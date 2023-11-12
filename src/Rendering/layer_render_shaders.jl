module LayerShaders

# Note: non-meshed versions of shaders are referred to as "preview" shaders.


#####################################
##    Uniforms

const UNIFORM_WORLD_VOXEL_OFFSET = "u_world_offset"
const UNIFORM_WORLD_SCALE = "u_world_scale"
const UNIFORM_MATRIX_VIEWPROJ = "u_mat_viewproj"
const UNIFORM_ELAPSED_SECONDS = "u_totalSeconds"
function set_universal_uniforms(prog::Program,
                                world_offset::v3f, world_scale::v3f,
                                elapsed_seconds::Float32,
                                matrix_view_proj::fmat4)
    set_uniform(prog, UNIFORM_WORLD_VOXEL_OFFSET, world_offset)
    set_uniform(prog, UNIFORM_WORLD_SCALE, world_scale)
    set_uniform(prog, UNIFORM_ELAPSED_SECONDS, elapsed_seconds)
    set_uniform(prog, UNIFORM_MATRIX_VIEWPROJ, matrix_view_proj)
end

const UNIFORM_PREVIEW_VOXEL_COUNT = "u_nVoxels"
const UNIFORM_PREVIEW_VOXEL_LAYER_IDX = "u_voxelLayer"
const UNIFORM_PREVIEW_VOXEL_TEX = "u_voxelGrid"
function set_preview_uniforms(prog::Program,
                              n_voxels::v3u,
                              layer_idx::Int,
                              voxel_tex::Texture)
    set_unifor(prog, "u_nVoxels", n_voxels)
    set_uniform(prog, "u_voxelLayer", layer_idx)
    set_uniform(prog, "u_voxelGrid", voxel_tex)
end

#####################################


#####################################
##    Building Blocks

const RELATIVE_PATH = "../assets/voxels"
const COMMON_INCLUDE_CODE = """
    #include <$RELATIVE_PATH/functions.shader>
    #include <$RELATIVE_PATH/noise.shader>
    #include <$RELATIVE_PATH/buffers.shader>

    uniform vec3 $UNIFORM_WORLD_VOXEL_OFFSET,
                 $UNIFORM_WORLD_SCALE;
    uniform float $UNIFORM_ELAPSED_SECONDS;

    //NOTE: ViewProj matrix is not necessarily the camera's matrix,
    //    e.x. when doing shadow maps it's the light source's.
    //For the camera's ViewProj matrix, refer to the camera UBO.
    uniform mat4 $UNIFORM_MATRIX_VIEWPROJ;
"""

# Fragment shader common setup:
const FRAG_SHADER_INPUTS = [
    # (input-only prefix, declaration)
    ("", "vec3 fIn_worldPos"),
    ("", "vec3 fIn_voxelPos"),
    ("", "vec2 fIn_uv"),
    ("flat", "uint fIn_packedFaceAxisDir")
]
const FRAG_SHADER_TOKEN_CUSTOM_OUTPUTS_DECL = "LAYER_CUSTOM_OUTPUTS_DECL"
const FRAG_SHADER_TOKEN_CUSTOM_OUTPUTS_IMPL = "LAYER_CUSTOM_OUTPUTS_IMPL"
const FRAG_SHADER_TOKEN_CUSTOM_INPUTS_DECL = "LAYER_CUSTOM_INPUTS_DECL"
"
Code that packs voxel vertex data for the fragment shader.
It happens in the vertex shader for meshed layers, and the geometry shader for preview layers.
"
const FRAG_SHADER_INPUT_PACKING = """
    //Declare all the outputs to the fragment shader.
    $((
        "out $n;" for (_, n) in FRAG_SHADER_INPUTS
    )...)
    #ifdef $FRAG_SHADER_TOKEN_CUSTOM_OUTPUTS_DECL
        $FRAG_SHADER_TOKEN_CUSTOM_OUTPUTS_DECL
    #endif

    //Packs a 0-3 axis value and -1/+1 direction value into the first 3 bits of a uint.
    uint packFaceData(uint axis, int dir)
    {
        uint bFaceDir = uint((dir + 1) / 2);
        return (axis << 1) | bFaceDir;
    }

    //Compute fragment shader inputs for a given vertex.
    struct ProcessedVert
    {
        vec3 voxelPos, worldPos;
        vec4 ndcPos;
        vec2 uv;
    };
    ProcessedVert processVertex(vec3 gridPos, uint axis)
    {
        //Compute world and NDC position.
        vec3 worldPos = $UNIFORM_WORLD_VOXEL_OFFSET + ($UNIFORM_WORLD_SCALE * gridPos);
        vec4 ndcPos = $UNIFORM_MATRIX_VIEWPROJ * vec4(worldPos, 1);

        // Calculate grid-space UV's based on which axis this face is perpendicular to.
        uvec2 uvIndices[3] = { ivec2(1, 2), ivec2(0, 2), ivec2(0, 1) };
        uvec2 uvIdx = uv_indices[axis];
        vec2 uv = vec2(gridPos[uvIdx.x], gridPos[uvIdx.y]);

        return ProcessedVert(gridPos, worldPos, ndcPos, uv);
    }
    void calcCustomOutputs(ProceessedVert vertex)
    {
        #ifdef $FRAG_SHADER_TOKEN_CUSTOM_OUTPUTS_IMPL
            $FRAG_SHADER_TOKEN_CUSTOM_OUTPUTS_IMPL
        #endif
    }
"""
const FRAG_SHADER_INPUT_UNPACKING = """
    //Declare all the inputs to the fragment shader.
    $((
        "in $p $n;" for (p, n) in FRAG_SHADER_INPUTS
    )...)
    #ifdef $FRAG_SHADER_TOKEN_CUSTOM_INPUTS_DECL
        $FRAG_SHADER_TOKEN_CUSTOM_INPUTS_DECL
    #endif

    //Declare the unpacked version of those inputs.
    struct InData
    {
        vec3 worldPos, voxelPos;
        vec3 worldNormal;
        vec2 uv;
        uint faceAxis;

        int faceDir; // -1 or +1
        uint bFaceDir; // 0 or 1
    };
    InData start()
    {
        uint faceAxis = fIn_packedFaceAxisDir >> 1,
             bFaceDir = fIn_packedFaceAxisDir & 0x1;
        int faceDir = int(bFaceDir * 2) - 1;

        vec3 worldNormal = vec3(0, 0, 0);
        worldNormal[faceAxis] = faceDir;

        return InData(
            fIn_worldPos, fIn_voxelPos,
            worldNormal,
            fIn_uv,
            faceAxis, faceDir, bFaceDir
        );
    }
"""

"Shader code providing functions to calculate fog, PBR lighting, etc"
const FORWARD_FX_SHADER_CODE = """
    //BRDF-related equations, using the "micro-facet" model.
    //Reference: https://learnopengl.com/PBR/Lighting

    //Approximates the light reflected from a surface, given its glancing angle.
    vec3 fresnelSchlick(float diffuseStrength, vec3 F0) {
        return F0 + ((1.0 - F0) * pow(1.0 - diffuseStrength, 5.0));
    }
    //Approximates the proportion of micro-facets
    //    which are facing the right way to reflect light into the camera.
    float distributionGGX(float specularStrength, float roughness) {
        float a   = roughness*roughness,
              a2  = a*a;

        float num   = a2;
        float denom = (specularStrength * specularStrength * (a2 - 1.0) + 1.0);
        denom = PI * denom * denom;

        return num / denom;
    }
    //Approximates the proportion of micro-facets which are visible
    //    to both the light and the camera.
    float geometrySchlickGGX(float diffuseStrength, float roughness) {
        float num   = diffuseStrength;
        float denom = diffuseStrength * (1.0 - roughness) + roughness;

        return diffuseStrength / ((diffuseStrength * (1.0 - roughness)) + roughness);
    }
    float geometrySmith(float diffuseNormalAndCamera,
                        float diffuseNormalAndLight,
                        float roughness) {
        float r = (roughness + 1.0);
        float k = (r*r) / 8.0;
        return geometrySchlickGGX(diffuseNormalAndCamera, k) *
               geometrySchlickGGX(diffuseNormalAndLight, k);
    }

    //Implements a microfacet lighting model, using approximations for various factors
    //    (see the functions above).
    vec3 microfacetLighting(vec3 normal, vec3 towardsCameraN, vec3 towardsLightN,
                            vec3 lightIrradiance,
                            vec3 albedo, float metallic, float roughness) {
        vec3 idealNormal = normalize(towardsLightN + towardsCameraN);

        float diffuseStrength = SATURATE(dot(normal, towardsLightN)),
              specularStrength = SATURATE(dot(idealNormal, normal)),
              normalClosenessToCamera = SATURATE(dot(normal, towardsCameraN));

        vec3 F0 = mix(vec3(0.04), albedo, metallic),
             F = fresnelSchlick(SATURATE(dot(idealNormal, towardsCameraN)), F0);

        vec3 energyOfReflection = F,
             energyOfDiffuse = (1.0 - energyOfReflection) * (1.0 - metallic);

        float NDF = distributionGGX(specularStrength, roughness),
              G = geometrySmith(normalClosenessToCamera, diffuseStrength, roughness);

        vec3 specular = F * (NDF * G / max(0.0001, 4.0 * normalClosenessToCamera * diffuseStrength));
        vec3 totalLight = (((energyOfDiffuse / PI) * albedo) + specular) *
                          lightIrradiance * diffuseStrength;

        return totalLight;
    }

    //Computes the amount of global height-fog between the camera and the fragment.
    vec3 computeFoggedColor(float camHeight,
                            float fragWorldHeight,
                            float fragDist3D, float fragDistVertical,
                            vec3 surfaceColor) {
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

        return mix(surfaceColor, u_fog.color.rgb, fogThickness);
    }

    //Computes ambient lighting.
    vec3 computeAmbient(vec3 surfacePos, vec3 normal, vec3 albedo)
    {
        //TODO: More interesting ambient term
        return vec3(0.03) * albedo;
    }

    //Computes shadow-maps.
    //Returns a 0-1 mask (0 is total shadow, 1 is fully-lit).
    float computeShadows(vec3 worldPos) {
        worldPos -= (u_sun.dir.xyz * u_sun.shadowBias);

        vec4 texel4 = u_sun.worldToTexelMat * vec4(worldPos, 1);
        vec3 texel = texel4.xyz / texel4.w;
        float shadowMask = texture(u_sun.shadowmap, texel).r;

        return shadowMask;
    }

    //Computes sky color.
    vec3 computeSkyColor(vec3 dir)
    {
        vec3 atmosphereColor = vec3(0.8, 0.825, 1.0);
        float sunSharpness = 256.0;

        float sunCloseness = max(0.0, dot(dir, -u_sun.dir.xyz));
        return atmosphereColor + pow(sunCloseness, sunSharpness);
    }
"""


#####################################


###############################
##    Shaders

# Shader source uses the '#line' preprocessor command
#    to help make it clearer where errors are coming from.

# Preview vertex shader:
const SHADER_PREVIEW_VERT = """
    #line 3000
    $COMMON_INCLUDE_CODE
    #line 4000

    //Dynamically decide in the geometry shader whether each face of each voxel should be rendered.
    uniform uvec3 $UNIFORM_PREVIEW_VOXEL_COUNT;

    out ivec3 gIn_voxelIdx; //Signed is more convenient for the geometry shader.

    void main() {
        //Convert from primitive index to voxel grid cell.
        ivec3 nVoxels = ivec3($UNIFORM_PREVIEW_VOXEL_COUNT);
        gIn_voxelIdx = ivec3(
            gl_VertexID % nVoxels.x,
            (gl_VertexID / u_nVoxels.x) % nVoxels.y,
            gl_VertexID / (nVoxels.x * nVoxels.y)
        );
    }
"""
# Preview goemetry shader:
const SHADER_PREVIEW_GEOM = """
    #line 3000
    $COMMON_INCLUDE_CODE
    #line 4000
    $FRAG_SHADER_INPUT_PACKING
    #line 5000

    uniform usampler3D $UNIFORM_PREVIEW_VOXEL_TEX;
    uniform uint $UNIFORM_PREVIEW_VOXEL_LAYER_IDX;

    layout (points) in;
    in ivec3 gIn_voxelIdx[];

    layout (triangle_strip, max_vertices=24) out;

    void main() {
        if (texelFetch($UNIFORM_PREVIEW_VOXEL_TEX, gIn_voxelIdx[0], 0).r != $UNIFORM_PREVIEW_VOXEL_LAYER_IDX)
            return;
        ivec3 texSize = textureSize($UNIFORM_PREVIEW_VOXEL_TEX, 0);

        for (int axis = 0; axis < 3; ++axis)
        {
            ivec2 otherAxesChoices[3] = {
                ivec2(1, 2),
                ivec2(0, 2),
                ivec2(0, 1)
            };
            ivec2 otherAxes = otherAxesChoices[axis];

            for (uint bDir = 0; bDir < 2; ++bDir)
            {
                int dir = (int(bDir) * 2) - 1;

                //Get the neighbor on this face.
                ivec3 neighborPos = gIn_voxelIdx[0];
                neighborPos[axis] += dir;
                //If the neighbor is past the edge of the voxel grid, assume it's empty space.
                uint neighborVoxel = 0;
                if (neighborPos[axis] >= 0 && neighborPos[axis] < texSize[axis])
                    neighborVoxel = texelFetch($UNIFORM_PREVIEW_VOXEL_TEX, neighborPos, 0).r;

                //If the neighbor is empty, then this face of our voxel should be rendered.
                if (neighborVoxel == 0)
                {
                    fIn_packedFaceAxisDir = packFaceData(axis, dir);

                    //Compute the 4 corners of this face, and emit a triangle strip for them.
                    vec3 minCorner = vec3(gIn_voxelIdx[0]);
                    const vec2 cornerFaceOffsets[4] = {
                        vec2(0, 0),
                        vec2(1, 0),
                        vec2(0, 1),
                        vec2(1, 1)
                    };
                    for (int cornerI = 0; cornerI < 4; ++cornerI)
                    {
                        vec3 corner = minCorner;
                        corner[axis] += bDir;
                        corner[otherAxes.x] += cornerFaceOffsets[cornerI].x;
                        corner[otherAxes.y] += cornerFaceOffsets[cornerI].y;

                        ProcessedVert gOut = processVertex(corner, axis);
                        fIn_worldPos = gOut.worldPos;
                        fIn_voxelPos = gOut.voxelPos;
                        fIn_uv = gOut.uv;
                        gl_Position = gOut.ndcPos;
                        //Note that fIn_packedFaceAxisDir was set above.
                        calcCustomOutputs(gOut);
                        EmitVertex();
                    }
                    EndPrimitive();
                }
            }
        }
    }
"""

# Meshed vertex shader:
const SHADER_MESHED_VERT = """
    #line 3000
    $COMMON_INCLUDE_CODE
    #line 4000
    $FRAG_SHADER_INPUT_PACKING
    #line 5000
    void main() {
        UnpackedVertexInput vIn = unpackInput(vIn_packedInput);

        fIn_packedFaceAxisDir = packFaceData(vIn.faceAxis, vIn.faceDir);

        ProcessedVert vOut = processVertex(vIn.voxelIdx, vIn.faceAxis);
        fIn_worldPos = vOut.worldPos;
        fIn_voxelPos = vOut.voxelPos;
        fIn_uv = vOut.uv;
        gl_Position = vOut.ndcPos;

        calcCustomOutputs(vOut);
    }
"""

# Header for all fragment shaders:
const SHADER_FRAG_HEADER = """
    #line 3000
    $COMMON_INCLUDE_CODE
    #line 4000
    $FRAG_SHADER_INPUT_UNPACKING
    #line 5000
    $FORWARD_FX_SHADER_CODE
    #line 6000
    uniform float $UNIFORM_ELAPSED_SECONDS;
    #line 7000
"""

###############################


export SHADER_PREVIEW_VERT, SHADER_PREVIEW_GEOM,
       SHADER_MESHED_VERT,
       SHADER_FRAG_HEADER,
       UNIFORM_WORLD_VOXEL_OFFSET, UNIFORM_WORLD_SCALE, UNIFORM_MATRIX_VIEWPROJ,
       UNIFORM_ELAPSED_SECONDS,
       UNIFORM_PREVIEW_VOXEL_COUNT, UNIFORM_PREVIEW_VOXEL_LAYER_IDX, UNIFORM_PREVIEW_VOXEL_TEX


end # module