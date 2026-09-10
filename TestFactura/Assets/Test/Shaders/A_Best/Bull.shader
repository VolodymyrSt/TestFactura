Shader "Custom/Bull"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)

        [Header(Base)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindSpeed ("Speed", Float) = 1
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0

        [Header(Root)]
        _TreeHeight ("Tree Height Mask", Float) = 5.0
        _RootStiffness ("Root Stiffness", Range(0, 1)) = 0.2

        [Header(Trunk)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind("Lean into Wind", Float) = 1.0
        _WindLeanWeight ("Wind Lean Static", Range(0, 1)) = 0.5
        _TrunkBend ("Trunk Bend", Float) = 0.5

        [Header(Branches)]
        _BranchStrength ("Branch Strength", Float) = 0.35
        _BranchFrequency ("Branch Frequency", Float) = 1.7
        _BranchTurbulence ("Branch Turbulence", Float) = 0.5

        [Header(Crowns Leaves)]
        _LeafFlutter ("Leaf Flutter", Float) = 0.2
        _LeafShimmer ("Leaf Shimmer", Range(0, 2)) = 0.4
        _LeafFrequency ("Leaf Frequency", Float) = 8.0

        [Header(Crown)]
        _CrownFollow ("Crown Follow Trunk", Range(0, 1)) = 0.5
        _CrownBias ("Crown Side Bias", Range(-1, 1)) = 0.0
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "Queue"="Geometry"
            "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma shader_feature _USE_WIND_ON
            #pragma shader_feature _LEAN_WIND

            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)

                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4, _BaseColor)

                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindSpeed)

                UNITY_DEFINE_INSTANCED_PROP(float, _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _RootStiffness)

                UNITY_DEFINE_INSTANCED_PROP(float, _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindLeanWeight)

                UNITY_DEFINE_INSTANCED_PROP(float, _BranchStrength)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchFrequency)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchTurbulence)

                UNITY_DEFINE_INSTANCED_PROP(float, _LeafFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float, _LeafShimmer)
                UNITY_DEFINE_INSTANCED_PROP(float, _LeafFrequency)

                UNITY_DEFINE_INSTANCED_PROP(float, _CrownFollow)
                UNITY_DEFINE_INSTANCED_PROP(float, _CrownBias)

                UNITY_DEFINE_INSTANCED_PROP(float, _WindPhase)

            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 worldPos = TransformObjectToWorld(float4(posOS, 1)).xyz;
                float3 pivotWS  = GetObjectToWorldMatrix()._m03_m13_m23;

                // =====================================================
                // HEIGHT MASK
                // =====================================================

                float treeH     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float stiffness = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootStiffness);

                float currentHeight = worldPos.y - pivotWS.y;

                float mask = saturate(
                    (currentHeight - (treeH * stiffness))
                    / max(0.001, treeH * (1.0 - stiffness))
                );

                float bendMask = smoothstep(0.0, 1.0, mask);

                // =====================================================
                // WIND
                // =====================================================

                float speed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);

                float time = (_Time.y * speed) + phase;

                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX),
                    0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.001
                ));

                float3 windPerp = float3(-windDir.z, 0, windDir.x);

                // =====================================================
                // RGB CHANNELS
                // =====================================================

                // R = trunk
                float trunkWeight = vColor.r;

                // B = branches
                float branchWeight = vColor.b;

                // G = crown / leaves
                float crownWeight = vColor.g;

                // =====================================================
                // SETTINGS
                // =====================================================

                float trunkBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);

                float branchStrength   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchStrength);
                float branchFrequency  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFrequency);
                float branchTurbulence = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchTurbulence);

                float leafFlutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeafFlutter);
                float leafShimmer = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeafShimmer);
                float leafFreq    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeafFrequency);

                float crownFollow = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollow);
                float crownBias   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownBias);

                // =====================================================
                // NOISE
                // =====================================================

                float noise =
                    frac(
                        sin(
                            dot(worldPos.xz, float2(12.9898, 78.233))
                        ) * 43758.5453
                    );

                // =====================================================
                // TRUNK
                // =====================================================

                float trunkWave;

                #if defined(_LEAN_WIND)

                    float staticLean =
                        trunkBend * leanWeight;

                    float dynamicSway =
                        sin(time)
                        * trunkBend
                        * (1.0 - leanWeight);

                    trunkWave =
                        (staticLean + dynamicSway)
                        * trunkWeight
                        * bendMask;

                #else

                    trunkWave =
                        sin(time)
                        * trunkBend
                        * trunkWeight
                        * bendMask;

                #endif

                // =====================================================
                // BRANCHES
                // =====================================================

                float branchPrimary =
                    sin(time * branchFrequency + noise * 4.0)
                    * branchStrength;

                float branchSecondary =
                    sin(time * (branchFrequency * 2.1) + noise * 7.0)
                    * branchStrength
                    * branchTurbulence;

                float branchFollow =
                    trunkWave
                    * crownFollow;

                float branchAlong =
                    (branchPrimary + branchSecondary + branchFollow)
                    * branchWeight;

                float branchCross =
                    branchSecondary
                    * 0.4
                    * branchWeight;

                // =====================================================
                // CROWN / LEAVES
                // =====================================================

                float shimmer =
                    sin(time * leafFreq + noise * 12.0)
                    * leafFlutter
                    * leafShimmer;

                float crownWave =
                    sin(time * (leafFreq * 0.5) + noise * 5.0)
                    * leafFlutter;

                float crownCross =
                    sin(time * (leafFreq * 0.7) + noise * 9.0)
                    * leafFlutter
                    * 0.5;

                float crownAlong =
                    (crownWave + shimmer)
                    * crownWeight;

                float crownSide =
                    (crownCross + crownBias)
                    * crownWeight;

                float crownVertical =
                    shimmer
                    * 0.25
                    * crownWeight;

                // =====================================================
                // OFFSETS
                // =====================================================

                float3 trunkOffset =
                    windDir
                    * trunkWave;

                float3 branchOffset =
                    windDir * branchAlong
                    + windPerp * branchCross;

                float3 crownOffset =
                    windDir * crownAlong
                    + windPerp * crownSide;

                // =====================================================
                // APPLY
                // =====================================================

                posOS.xyz += trunkOffset * bendMask;
                posOS.xyz += branchOffset * bendMask;
                posOS.xyz += crownOffset * bendMask;

                posOS.y += crownVertical;
                posOS.y += trunkWave * 0.08 * bendMask;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos =
                    ApplyWind(v.positionOS.xyz, v.color);

                o.positionHCS =
                    TransformObjectToHClip(float4(animatedPos, 1));

                o.positionWS =
                    TransformObjectToWorld(float4(animatedPos, 1)).xyz;

                float4 st =
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);

                o.uv =
                    v.uv * st.xy + st.zw;

                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                half4 baseCol =
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);

                half4 tex =
                    SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                float3 dx = ddx(i.positionWS);
                float3 dy = ddy(i.positionWS);

                float3 normalWS =
                    normalize(cross(dx, dy));

                Light mainLight = GetMainLight();

                float NdotL =
                    saturate(dot(normalWS, mainLight.direction));

                float3 lighting =
                    mainLight.color * (NdotL + 0.25);

                return half4(
                    tex.rgb * baseCol.rgb * lighting,
                    tex.a
                );
            }

            ENDHLSL
        }
    }
}