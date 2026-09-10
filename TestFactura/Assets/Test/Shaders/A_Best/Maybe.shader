Shader "Custom/Tree_Wind_Instanced"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Base)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindSpeed ("Speed", Float) = 1
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0

        [Header(Root)]
        _TreeHeight ("Tree Height Mask", Float) = 5.0
        _RootStiffness ("Root Stiffness", Range(0,1)) = 0.2

        [Header(Lean)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind("Lean into Wind", Float) = 1.0
        _WindLeanWeight ("Wind Lean Static", Range(0,1)) = 0.5

        [Header(Trunk)]
        _TrunkBend ("Trunk Bend", Float) = 0.25

        [Header(Branch)]
        _BranchBend ("Branch Bend", Float) = 0.12
        _BranchSpeed ("Branch Speed", Float) = 1.4
        _BranchPhase ("Branch Phase Offset", Float) = 0.7
        _BranchFlutter ("Branch Flutter", Float) = 0.05
        _ShimmerIntensity ("Shimmer Intensity", Range(0,2)) = 0.25

        [Header(Crown)]
        _CrownFollowStrength ("Crown Follow Strength", Range(0,1)) = 0.55

        [HideInInspector] _WindPhase ("", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"="TransparentCutout"
            "Queue"="AlphaTest"
            "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // Локальні шейдер-флешки
            #pragma shader_feature_local _USE_WIND_ON
            #pragma shader_feature_local _LEAN_WIND
            #pragma shader_feature_local _ALPHATEST_ON

            #pragma multi_compile_instancing
            #pragma multi_compile_fog

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            // Інстансінг буфер
            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4, _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)

                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindSpeed)

                UNITY_DEFINE_INSTANCED_PROP(float, _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _RootStiffness)

                UNITY_DEFINE_INSTANCED_PROP(float, _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindLeanWeight)

                UNITY_DEFINE_INSTANCED_PROP(float, _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchPhase)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchFlutter)

                UNITY_DEFINE_INSTANCED_PROP(float, _WindPhase)
                UNITY_DEFINE_INSTANCED_PROP(float, _ShimmerIntensity)
                UNITY_DEFINE_INSTANCED_PROP(float, _CrownFollowStrength)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float fogFactor    : TEXCOORD3;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // Хеш-функція для шуму
            float Hash13(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.yzx + 33.33);
                return frac((p.x + p.y) * p.z);
            }

            // Функція застосування вітру
            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 worldPos = TransformObjectToWorld(posOS);

                float treeHeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float rootStiff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootStiffness);

                float normalizedHeight = saturate((worldPos.y - pivotWS.y) / max(treeHeight, 0.001));

                float trunkMask = smoothstep(rootStiff, 1.0, normalizedHeight);

                float phase = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float time = _Time.y * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);

                float3 windDirLocal = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX),
                    0.0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ)
                ));

                float3 windDir = normalize(TransformObjectToWorldDir(windDirLocal));

                // Буровий ствол
                float trunkBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float trunkWave;

                #if defined(_LEAN_WIND)
                    float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);
                    float gust = sin(time + phase) * (1.0 - leanWeight);
                    trunkWave = (leanWeight + gust) * trunkBend;
                #else
                    trunkWave = sin(time + phase) * trunkBend;
                #endif

                trunkWave *= trunkMask * trunkMask;

                float3 trunkOffsetWS = windDir * trunkWave;
                float3 trunkOffsetOS = TransformWorldToObjectDir(trunkOffsetWS);
                posOS.xz += trunkOffsetOS.xz;

                // Ветви
                float branchMask = vColor.b;
                float branchTime = (_Time.y * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed))
                                    + phase + UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchPhase);
                float branchNoise = Hash13(worldPos * 0.25);

                float branchWave = sin(branchTime + branchNoise * 6.28) * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);

                float trunkSmooth = smoothstep(0.0, 0.3, trunkMask) * trunkMask * trunkMask;
                branchWave *= trunkSmooth;

                float3 branchOffsetWS = windDir * branchWave;
                float3 branchOffsetOS = TransformWorldToObjectDir(branchOffsetWS);
                posOS.xz += branchOffsetOS.xz;

                // Крона
                float crownMask = vColor.g;
                float flutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                float shimmer = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ShimmerIntensity);
                float leafNoise = Hash13(worldPos * 2.3);
                float heightDampen = 1.0 - normalizedHeight * 0.7;
                float followStrength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollowStrength);

                float3 inheritedMotion = branchOffset * crownMask * followStrength * heightDampen;

                float flutterWave = sin(time * 3.5 + leafNoise * 12.0);
                float shimmerWave = sin(time * 11.0 + leafNoise * 25.0);

                float localFlutter = (flutterWave * flutter + shimmerWave * flutter * shimmer * 0.4) * heightDampen;
                localFlutter *= crownMask;

                // Застосування inherited motion
                posOS.xyz += inheritedMotion;

                // Листяний flutter
                posOS.xz += windDir.xz * localFlutter * 0.08;
                posOS.y += localFlutter * 0.03;

                return posOS;
            }

            // Вершинна функція
            Varyings vert(Attributes v)
            {
                UNITY_SETUP_INSTANCE_ID(v);
                Varyings o;

                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);

                VertexPositionInputs posInputs = GetVertexPositionInputs(animatedPos);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normalOS);

                o.positionHCS = posInputs.positionCS;
                o.positionWS = posInputs.positionWS;
                o.normalWS = normalInputs.normalWS;

                o.fogFactor = ComputeFogFactor(posInputs.positionCS.z);

                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;

                return o;
            }

            // Фрагментна функція
            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col = tex * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);

                #ifdef _ALPHATEST_ON
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif

                float3 normalWS = normalize(IN.normalWS);
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                float NdotL = saturate(dot(normalWS, mainLight.direction));
                float3 diffuse = mainLight.color * NdotL * mainLight.shadowAttenuation;
                float3 ambient = SampleSH(normalWS);

                col.rgb *= diffuse + ambient;
                col.rgb = MixFog(col.rgb, IN.fogFactor);

                return col;
            }

            ENDHLSL
        }
    }
}