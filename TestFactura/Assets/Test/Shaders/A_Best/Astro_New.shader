Shader "Custom/Tree_Wind_Proper_Full"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Wind Global)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindSpeed ("Wind Speed", Float) = 1.0
        _WindDir ("Wind Direction", Vector) = (1,0,0.5,0)
        _WindStrength ("Wind Strength", Range(0,2)) = 0.7

        [Header(Trunk Bending)]
        _TrunkBend ("Trunk Bend Amount", Range(0,1)) = 0.3
        _TrunkStart ("Trunk Bend Start Height", Range(0,1)) = 0.15
        _TrunkFalloff ("Trunk Bend Falloff", Range(0.1,1)) = 0.5

        [Header(Branch Hierarchy)]
        _BranchBend ("Branch Bend Amount", Range(0,1)) = 0.5
        _BranchSpeed ("Branch Speed", Range(0.5,2)) = 1.2
        [Toggle(_BRANCH_AFFECT_BY_ROOT)] _BranchAffectedByRoot("Branches Affected by Root Stiffness", Float) = 1.0
        
        [Header(Crown)]
        _CrownShimmer ("Crown Shimmer Amount", Range(0,0.1)) = 0.02
        _CrownShimmerSpeed ("Crown Shimmer Speed", Float) = 8.0
        [Toggle(_CROWN_AFFECT_BY_ROOT)] _CrownAffectedByRoot("Crown Affected by Root Stiffness", Float) = 1.0
        
        [Header(Phase Randomization)]
        _PhaseRand ("Phase Random Scale", Range(0,3)) = 1.5

        [HideInInspector] _WindPhase ("Wind Phase", Float) = 0
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
            #pragma shader_feature _BRANCH_AFFECT_BY_ROOT
            #pragma shader_feature _CROWN_AFFECT_BY_ROOT
            #pragma shader_feature _ALPHATEST_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            
            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
                UNITY_DEFINE_INSTANCED_PROP(float4, _WindDir)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkStart)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkFalloff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmer)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmerSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _PhaseRand)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindPhase)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                // R=branch weight, G=crown weight, B=phase random, A=stiffness bonus
                // Vertex colors are used ONLY as wind masks — never rendered as surface color
                float4 color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float fogFactor    : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // ===== ROTATION UTILITIES =====
            float3 RotateAroundPivot(float3 pos, float3 pivot, float3 axis, float angle)
            {
                float3 local = pos - pivot;
                float c = cos(angle);
                float s = sin(angle);
                float dotAxis = dot(local, axis);
                float3 crossAxis = cross(axis, local);
                float3 rotated = local * c + crossAxis * s + axis * dotAxis * (1.0 - c);
                return pivot + rotated;
            }
            
            float SmoothHeightMask(float currentHeight, float treeHeight, float start, float falloff)
            {
                float rawMask = saturate((currentHeight - treeHeight * start) / max(0.001, treeHeight * falloff));
                return rawMask * rawMask * (3.0 - 2.0 * rawMask);
            }
            
            float GetRootMask(float currentHeight, float treeHeight, float stiffness)
            {
                float mask = saturate((currentHeight - (treeHeight * stiffness)) / 
                                      max(0.001, treeHeight * (1.0 - stiffness)));
                return mask * mask * (3.0 - 2.0 * mask);
            }

            // ===== MAIN WIND LOGIC =====
            float3 ApplyWindHierarchy(float3 posOS, float3 normalOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif
                
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                
                // Estimate tree height from object bounds via matrix scale
                float3 scale = float3(
                    length(GetObjectToWorldMatrix()._m00_m10_m20),
                    length(GetObjectToWorldMatrix()._m01_m11_m21),
                    length(GetObjectToWorldMatrix()._m02_m12_m22)
                );
                float treeHeight = scale.y;
                if (treeHeight < 0.01) treeHeight = 5.0;
                
                float currentHeight = max(0.0, worldPos.y - pivotWS.y);
                
                // ===== VERTEX COLOR MASKS (wind only, not rendered) =====
                float branchWeight   = vColor.r; // FIX: was vColor.b in original ForwardLit
                float crownWeight    = vColor.g;
                float phaseRand      = vColor.b * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _PhaseRand);
                float stiffnessBonus = vColor.a;
                
                // ===== WIND PARAMETERS =====
                float windSpeed    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float windStrength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
                float phase        = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float globalTime   = _Time.y * windSpeed + phase + phaseRand;
                
                float3 windDir = normalize(UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDir).xyz);
                windDir.y = 0;
                if (length(windDir) < 0.001) windDir = float3(1, 0, 0);
                
                // ===== TRUNK BENDING =====
                float trunkBend    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float trunkStart   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkStart);
                float trunkFalloff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkFalloff);
                
                float trunkMask  = SmoothHeightMask(currentHeight, treeHeight, trunkStart, trunkFalloff);
                float trunkAngle = sin(globalTime * 0.8) * trunkBend * windStrength * trunkMask;
                
                float3 trunkAxis = normalize(cross(float3(0,1,0), windDir));
                if (length(trunkAxis) < 0.001) trunkAxis = float3(1,0,0);
                float3 trunkRotatedPos = RotateAroundPivot(posOS, float3(0,0,0), trunkAxis, trunkAngle);
                
                // ===== ROOT STIFFNESS =====
                float rootStiffness  = 0.2;
                float rootMask       = GetRootMask(currentHeight, treeHeight, rootStiffness);
                float finalRootMask  = rootMask * (1.0 - stiffnessBonus * 0.5);
                
                // ===== BRANCH BENDING =====
                float branchBend  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
                float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchTime  = _Time.y * branchSpeed + phase + phaseRand * 2.0;
                
                float3 branchPivot    = float3(0, trunkRotatedPos.y, 0);
                float branchAngleBase = sin(branchTime) * branchBend * windStrength * branchWeight;
                
                #if defined(_BRANCH_AFFECT_BY_ROOT)
                    float branchAngle = branchAngleBase * finalRootMask;
                #else
                    float branchAngle = branchAngleBase;
                #endif
                
                float3 branchAxis      = normalize(cross(windDir, float3(0,1,0)) + float3(0,0.5,0));
                float3 branchRotatedPos = RotateAroundPivot(trunkRotatedPos, branchPivot, branchAxis, branchAngle);
                branchRotatedPos.y    -= abs(branchAngle) * branchWeight * 0.1;
                
                // ===== CROWN SHIMMER =====
                float crownShimmer      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmer);
                float crownShimmerSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmerSpeed);
                
                // Use original OS position for stable noise (prevents boiling)
                float noise1 = frac(dot(posOS, float3(12.9898,  78.233,  45.5432)));
                float noise2 = frac(dot(posOS, float3(37.7193,  23.1415, 91.6734)));
                float noise3 = frac(dot(posOS, float3(93.7879,  41.2345, 67.8912)));
                
                float shimmerXZ        = sin(_Time.y * crownShimmerSpeed       + noise1 * 15.0) * crownShimmer * crownWeight;
                float shimmerY         = cos(_Time.y * crownShimmerSpeed * 0.7 + noise2 * 12.0) * crownShimmer * 0.5 * crownWeight;
                float shimmerSecondary = sin(_Time.y * crownShimmerSpeed * 1.3 + noise3 * 18.0) * crownShimmer * 0.3 * crownWeight;
                
                #if defined(_CROWN_AFFECT_BY_ROOT)
                    shimmerXZ        *= finalRootMask;
                    shimmerY         *= finalRootMask;
                    shimmerSecondary *= finalRootMask;
                #endif
                
                float3 finalPos  = branchRotatedPos;
                finalPos.xz     += windDir.xz * shimmerXZ;
                finalPos.y      += shimmerY + shimmerSecondary;
                
                // ===== LEAF TURBULENCE =====
                float leafTurbulence  = sin(globalTime * 12.0 + noise1 * 30.0) * crownShimmer * crownWeight * 0.5;
                leafTurbulence       *= saturate(currentHeight / treeHeight);
                
                #if defined(_CROWN_AFFECT_BY_ROOT)
                    leafTurbulence *= finalRootMask;
                #endif
                
                finalPos.xz += windDir.xz * leafTurbulence * 0.5;
                
                return finalPos;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                
                float3 animatedPos = ApplyWindHierarchy(v.positionOS.xyz, v.normalOS, v.color);
                
                float4 posWS   = mul(GetObjectToWorldMatrix(), float4(animatedPos, 1));
                o.positionWS   = posWS.xyz;
                o.positionCS   = TransformWorldToHClip(posWS);
                o.normalWS     = TransformObjectToWorldNormal(v.normalOS);
                
                float4 baseST  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv           = v.uv * baseST.xy + baseST.zw;
                o.fogFactor    = ComputeFogFactor(o.positionCS.z);
                
                return o;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                
                // Sample albedo texture — vertex colors are NOT used here
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col      = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                
                #ifdef _ALPHATEST_ON
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif
                
                float3 normalWS  = normalize(IN.normalWS);
                Light mainLight  = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float  NdotL     = saturate(dot(normalWS, mainLight.direction));
                float3 diffuse   = mainLight.color * mainLight.shadowAttenuation * NdotL;
                float3 ambient   = SampleSH(normalWS);
                
                col.rgb *= (diffuse + ambient);
                col.rgb  = MixFog(col.rgb, IN.fogFactor);
                
                return col;
            }
            ENDHLSL
        }
        
        // ===== SHADOW CASTER PASS =====
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
            #pragma shader_feature _BRANCH_AFFECT_BY_ROOT
            #pragma shader_feature _CROWN_AFFECT_BY_ROOT
            #pragma shader_feature _ALPHATEST_ON
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            
            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
                UNITY_DEFINE_INSTANCED_PROP(float4, _WindDir)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkStart)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkFalloff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmer)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmerSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _PhaseRand)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindPhase)
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
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            float3 RotateAroundPivot(float3 pos, float3 pivot, float3 axis, float angle)
            {
                float3 local    = pos - pivot;
                float  c        = cos(angle);
                float  s        = sin(angle);
                float  dotAxis  = dot(local, axis);
                float3 crossAxis = cross(axis, local);
                float3 rotated  = local * c + crossAxis * s + axis * dotAxis * (1.0 - c);
                return pivot + rotated;
            }
            
            float SmoothHeightMask(float currentHeight, float treeHeight, float start, float falloff)
            {
                float rawMask = saturate((currentHeight - treeHeight * start) / max(0.001, treeHeight * falloff));
                return rawMask * rawMask * (3.0 - 2.0 * rawMask);
            }
            
            float GetRootMask(float currentHeight, float treeHeight, float stiffness)
            {
                float mask = saturate((currentHeight - (treeHeight * stiffness)) / 
                                      max(0.001, treeHeight * (1.0 - stiffness)));
                return mask * mask * (3.0 - 2.0 * mask);
            }
            
            float3 ApplyWindHierarchy(float3 posOS, float3 normalOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif
                
                float3 pivotWS  = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                
                float3 scale = float3(
                    length(GetObjectToWorldMatrix()._m00_m10_m20),
                    length(GetObjectToWorldMatrix()._m01_m11_m21),
                    length(GetObjectToWorldMatrix()._m02_m12_m22)
                );
                float treeHeight = scale.y;
                if (treeHeight < 0.01) treeHeight = 5.0;
                
                float currentHeight = max(0.0, worldPos.y - pivotWS.y);
                
                float branchWeight   = vColor.r;
                float crownWeight    = vColor.g;
                float phaseRand      = vColor.b * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _PhaseRand);
                float stiffnessBonus = vColor.a;
                
                float windSpeed    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float windStrength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
                float phase        = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float globalTime   = _Time.y * windSpeed + phase + phaseRand;
                
                float3 windDir = normalize(UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDir).xyz);
                windDir.y = 0;
                if (length(windDir) < 0.001) windDir = float3(1, 0, 0);
                
                float trunkBend    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float trunkStart   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkStart);
                float trunkFalloff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkFalloff);
                
                float trunkMask  = SmoothHeightMask(currentHeight, treeHeight, trunkStart, trunkFalloff);
                float trunkAngle = sin(globalTime * 0.8) * trunkBend * windStrength * trunkMask;
                
                float3 trunkAxis = normalize(cross(float3(0,1,0), windDir));
                if (length(trunkAxis) < 0.001) trunkAxis = float3(1,0,0);
                float3 trunkRotatedPos = RotateAroundPivot(posOS, float3(0,0,0), trunkAxis, trunkAngle);
                
                float rootStiffness = 0.2;
                float rootMask      = GetRootMask(currentHeight, treeHeight, rootStiffness);
                float finalRootMask = rootMask * (1.0 - stiffnessBonus * 0.5);
                
                float branchBend  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
                float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchTime  = _Time.y * branchSpeed + phase + phaseRand * 2.0;
                
                float3 branchPivot    = float3(0, trunkRotatedPos.y, 0);
                float branchAngleBase = sin(branchTime) * branchBend * windStrength * branchWeight;
                
                #if defined(_BRANCH_AFFECT_BY_ROOT)
                    float branchAngle = branchAngleBase * finalRootMask;
                #else
                    float branchAngle = branchAngleBase;
                #endif
                
                float3 branchAxis       = normalize(cross(windDir, float3(0,1,0)) + float3(0,0.5,0));
                float3 branchRotatedPos = RotateAroundPivot(trunkRotatedPos, branchPivot, branchAxis, branchAngle);
                branchRotatedPos.y     -= abs(branchAngle) * branchWeight * 0.1;
                
                float crownShimmer      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmer);
                float crownShimmerSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmerSpeed);
                
                float noise1 = frac(dot(posOS, float3(12.9898,  78.233,  45.5432)));
                float noise2 = frac(dot(posOS, float3(37.7193,  23.1415, 91.6734)));
                float noise3 = frac(dot(posOS, float3(93.7879,  41.2345, 67.8912)));
                
                float shimmerXZ        = sin(_Time.y * crownShimmerSpeed       + noise1 * 15.0) * crownShimmer * crownWeight;
                float shimmerY         = cos(_Time.y * crownShimmerSpeed * 0.7 + noise2 * 12.0) * crownShimmer * 0.5 * crownWeight;
                float shimmerSecondary = sin(_Time.y * crownShimmerSpeed * 1.3 + noise3 * 18.0) * crownShimmer * 0.3 * crownWeight;
                
                #if defined(_CROWN_AFFECT_BY_ROOT)
                    shimmerXZ        *= finalRootMask;
                    shimmerY         *= finalRootMask;
                    shimmerSecondary *= finalRootMask;
                #endif
                
                float3 finalPos  = branchRotatedPos;
                finalPos.xz     += windDir.xz * shimmerXZ;
                finalPos.y      += shimmerY + shimmerSecondary;
                
                return finalPos;
            }
            
            Varyings vertShadow(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                
                float3 animatedPos = ApplyWindHierarchy(v.positionOS.xyz, v.normalOS, v.color);
                
                float4 baseST  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv           = v.uv * baseST.xy + baseST.zw;
                
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                float3 posWS    = TransformObjectToWorld(float4(animatedPos, 1)).xyz;
                o.positionCS    = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, 0));
                
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
    
    Fallback "Universal Render Pipeline/Lit"
}
