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
        _TrunkBend ("Trunk Bend", Float) = 0.5

        [Header(Branch)]
        _BranchBend    ("Branch Bend",          Float) = 0.3
        _BranchSpeed   ("Branch Speed",         Float) = 1.3
        _BranchPhase   ("Branch Phase Offset",  Float) = 0.7
        _BranchFlutter ("Branch Flutter",       Float) = 0.2
        _ShimmerIntensity ("Shimmer Intensity", Range(0,2)) = 0.4

        [Header(Crown)]
        _CrownFollowStrength ("Crown Follow Strength", Range(0,1)) = 0.5

        [HideInInspector] _WindPhase ("", Float) = 0
        [HideInInspector] _MainLightPosition ("", Vector) = (0,0,0,0)
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _USE_WIND_ON
            #pragma shader_feature _LEAN_WIND
            #pragma shader_feature _ALPHATEST_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindLeanWeight)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchPhase)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float,  _RootStiffness)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindPhase)
                UNITY_DEFINE_INSTANCED_PROP(float,  _ShimmerIntensity)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownFollowStrength)
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
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float  fogFactor   : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor, float3 normalOS)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                // Зберігаємо оригінальну позицію (без вітру) для стабільного шуму листя
                float3 originalPosOS = posOS;

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                float3 pivotWS  = GetObjectToWorldMatrix()._m03_m13_m23;

                float treeH         = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float stiffness     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootStiffness);
                float currentHeight = worldPos.y - pivotWS.y;

                float mask = saturate((currentHeight - (treeH * stiffness)) / max(0.001, treeH * (1.0 - stiffness)));

                float wSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float time   = (_Time.y * wSpeed) + phase;

                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.001));

                //TRUNK ──────────────────────────────────────────
                float tBend      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);
                float trunkWave;

                #if defined(_LEAN_WIND)
                    trunkWave = (tBend * leanWeight + sin(time) * tBend * (1.0 - leanWeight)) * mask;
                #else
                    trunkWave = sin(time) * tBend * mask;
                #endif

                posOS.xz += windDir.xz * trunkWave;

                //BRANCH ─────────────────────────────────────────
                float branchMask     = vColor.b;
                float branchBendAmt  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
                float branchSpeed    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchPhaseOff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchPhase);
                float branchTime     = (_Time.y * branchSpeed) + phase + branchPhaseOff;

                float distFromTrunk = length(posOS.xz); // використовується позиція після trunk (допустимо)
                float branchAngle   = sin(branchTime) * branchBendAmt * branchMask;

                posOS.xz += windDir.xz * branchAngle * distFromTrunk;
                posOS.y  -= abs(branchAngle) * distFromTrunk * 0.3;

                //CROWN ──────────────────────────────────────────
                float flutter    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                float leafWeight = vColor.g;

                // Використовуємо ОРИГІНАЛЬНУ позицію для стабільного шуму — не змінюється від trunk/branch
                float leafNoise  = frac(dot(originalPosOS.xyz, float3(12.9898, 78.233, 45.164)));

                float shimmer      = sin(time * 14.0 + leafNoise * 20.0) * flutter
                                     * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ShimmerIntensity);
                float leafWave     = sin(time * 2.5 + leafNoise * 6.0) * flutter;
                float leafMotionXZ = (leafWave + shimmer) * leafWeight;
                float leafMotionY  = shimmer * leafWeight * 0.3;

                posOS.xz += windDir.xz * leafMotionXZ;
                posOS.y  += leafMotionY;

                // крона слідує за гілками (без distFromTrunk)
                float followStr   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollowStrength);
                float crownFollow = sin(branchTime) * branchBendAmt * leafWeight * followStr;
                posOS.xz += windDir.xz * crownFollow;
                posOS.y  -= abs(crownFollow) * 0.15;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color, v.normalOS);

                o.positionHCS = TransformObjectToHClip(float4(animatedPos, 1));
                o.positionWS  = TransformObjectToWorld(float4(animatedPos, 1)).xyz;
                o.normalWS    = TransformObjectToWorldNormal(v.normalOS);
                o.fogFactor   = ComputeFogFactor(o.positionHCS.z);

                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;

                return o;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col      = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);

                #ifdef _ALPHATEST_ON
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif

                float3 nWS       = normalize(IN.normalWS);
                Light  mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float  NdotL     = saturate(dot(nWS, mainLight.direction));
                float3 diffuse   = mainLight.color * mainLight.shadowAttenuation * NdotL;
                float3 ambient   = SampleSH(nWS);

                col.rgb *= (diffuse + ambient);
                col.rgb  = MixFog(col.rgb, IN.fogFactor);

                return col;
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma shader_feature _USE_WIND_ON
            #pragma shader_feature _LEAN_WIND
            #pragma shader_feature _ALPHATEST_ON
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindLeanWeight)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchPhase)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float,  _RootStiffness)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindPhase)
                UNITY_DEFINE_INSTANCED_PROP(float,  _ShimmerIntensity)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownFollowStrength)
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
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor, float3 normalOS)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                // Зберігаємо оригінальну позицію для стабільного шуму листя
                float3 originalPosOS = posOS;

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                float3 pivotWS  = GetObjectToWorldMatrix()._m03_m13_m23;

                float treeH         = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float stiffness     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootStiffness);
                float currentHeight = worldPos.y - pivotWS.y;

                float mask = saturate((currentHeight - (treeH * stiffness)) / max(0.001, treeH * (1.0 - stiffness)));

                float wSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float time   = (_Time.y * wSpeed) + phase;

                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.001));

                // ── 1. TRUNK ──────────────────────────────────────────
                float tBend      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);
                float trunkWave;

                #if defined(_LEAN_WIND)
                    trunkWave = (tBend * leanWeight + sin(time) * tBend * (1.0 - leanWeight)) * mask;
                #else
                    trunkWave = sin(time) * tBend * mask;
                #endif

                posOS.xz += windDir.xz * trunkWave;

                // ── 2. BRANCH ─────────────────────────────────────────
                float branchMask     = vColor.b;
                float branchBendAmt  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
                float branchSpeed    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchPhaseOff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchPhase);
                float branchTime     = (_Time.y * branchSpeed) + phase + branchPhaseOff;

                float distFromTrunk = length(posOS.xz);
                float branchAngle   = sin(branchTime) * branchBendAmt * branchMask;

                posOS.xz += windDir.xz * branchAngle * distFromTrunk;
                posOS.y  -= abs(branchAngle) * distFromTrunk * 0.3;

                // ── 3. CROWN ──────────────────────────────────────────
                float flutter    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                float leafWeight = vColor.g;

                // Використовуємо ОРИГІНАЛЬНУ позицію для стабільного шуму
                float leafNoise  = frac(dot(originalPosOS.xyz, float3(12.9898, 78.233, 45.164)));

                float shimmer      = sin(time * 14.0 + leafNoise * 20.0) * flutter
                                     * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ShimmerIntensity);
                float leafWave     = sin(time * 2.5 + leafNoise * 6.0) * flutter;
                float leafMotionXZ = (leafWave + shimmer) * leafWeight;
                float leafMotionY  = shimmer * leafWeight * 0.3;

                posOS.xz += windDir.xz * leafMotionXZ;
                posOS.y  += leafMotionY;

                // ──► крона слідує за гілками
                float followStr   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollowStrength);
                float crownFollow = sin(branchTime) * branchBendAmt * leafWeight * followStr;
                posOS.xz += windDir.xz * crownFollow;
                posOS.y  -= abs(crownFollow) * 0.15;

                return posOS;
            }

            Varyings vertShadow(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color, v.normalOS);

                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;

                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                float4 posWS    = float4(TransformObjectToWorld(float4(animatedPos, 1)).xyz, 1);
                o.positionHCS   = TransformWorldToHClip(ApplyShadowBias(posWS.xyz, normalWS, 0));

                return o;
            }

            half4 fragShadow(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                #ifdef _ALPHATEST_ON
                    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    half4 col      = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif
                return 0;
            }

            ENDHLSL
        }
    }
}