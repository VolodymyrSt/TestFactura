Shader "Custom/Tree_Wind_Working"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Wind Global)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindSpeed ("Wind Speed", Float) = 1.0
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1.0
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0.5
        _WindStrength ("Wind Strength", Range(0,2)) = 0.7

        [Header(Trunk)]
        _TrunkBend ("Trunk Bend Amount", Range(0,0.8)) = 0.25
        _TrunkStart ("Trunk Bend Start", Range(0,0.5)) = 0.15
        _TrunkFalloff ("Trunk Bend Smoothness", Range(0.1,1)) = 0.4

        [Header(Branch)]
        _BranchBend ("Branch Bend Amount", Range(0,1.2)) = 0.6
        _BranchSpeed ("Branch Speed", Range(0.5,2.5)) = 1.3
        _BranchFlutter ("Branch Flutter", Range(0,0.5)) = 0.15

        [Header(Crown)]
        _CrownFollow ("Crown Follow Branch", Range(0,1)) = 0.8
        _CrownShimmer ("Crown Shimmer", Range(0,0.15)) = 0.04
        _CrownShimmerSpeed ("Shimmer Speed", Float) = 10.0

        [Header(Lean)]
        [Toggle(_LEAN_ENABLED)] _LeanEnabled("Enable Lean into Wind", Float) = 1.0
        _LeanAmount ("Lean Amount", Range(0,1)) = 0.15

        [Header(Phase)]
        _PhaseRand ("Random Phase Scale", Range(0,3)) = 1.5

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
            #pragma shader_feature _LEAN_ENABLED
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
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkStart)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkFalloff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownFollow)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmer)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmerSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _LeanAmount)
                UNITY_DEFINE_INSTANCED_PROP(float,  _PhaseRand)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindPhase)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR; // R=branch weight, G=crown weight, B=random, A=unused
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

            // ===== SIMPLE ROTATION FUNCTION =====
            float3 RotateY(float3 pos, float angle)
            {
                float s = sin(angle);
                float c = cos(angle);
                return float3(pos.x * c - pos.z * s, pos.y, pos.x * s + pos.z * c);
            }
            
            float3 RotateAroundPoint(float3 pos, float3 pivot, float3 axis, float angle)
            {
                float3 dir = pos - pivot;
                float c = cos(angle);
                float s = sin(angle);
                float dotAxis = dot(dir, axis);
                float3 crossAxis = cross(axis, dir);
                return pivot + dir * c + crossAxis * s + axis * dotAxis * (1 - c);
            }

            // ===== SMOOTH HEIGHT MASK =====
            float GetHeightMask(float height, float treeH, float start, float falloff)
            {
                float raw = saturate((height - treeH * start) / max(0.001, treeH * falloff));
                return raw * raw * (3.0 - 2.0 * raw); // Smooth cubic
            }

            float3 ApplyWind(float3 posOS, float4 vColor, float3 normalOS)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif
                
                // Get tree dimensions
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                float treeHeight = abs(GetObjectToWorldMatrix()._m13 - pivotWS.y);
                if (treeHeight < 0.01) treeHeight = 5.0;
                float currentHeight = max(0, worldPos.y - pivotWS.y);
                
                // Extract vertex colors
                float branchInfluence = vColor.r;      // R: 0=trunk, 1=branch tip
                float crownInfluence = vColor.g;       // G: 0=wood, 1=leaf
                float phaseRand = vColor.b * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _PhaseRand);
                
                // Wind parameters
                float speed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float strength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
                float time = _Time.y * speed + phase + phaseRand;
                
                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ)
                ));
                
                // ===== 1. TRUNK BENDING =====
                float trunkBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float trunkStart = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkStart);
                float trunkFalloff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkFalloff);
                
                float trunkMask = GetHeightMask(currentHeight, treeHeight, trunkStart, trunkFalloff);
                
                // Main trunk wave
                float trunkWave = sin(time * 0.8) * trunkBend * strength * trunkMask;
                
                // Lean into wind (constant bend)
                #if defined(_LEAN_ENABLED)
                    float leanAmount = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeanAmount);
                    float lean = leanAmount * strength * trunkMask;
                    trunkWave += lean;
                #endif
                
                // Apply trunk rotation (bend in wind direction)
                float3 trunkAxis = normalize(cross(float3(0,1,0), windDir));
                if (length(trunkAxis) < 0.01) trunkAxis = float3(1,0,0);
                float3 posAfterTrunk = RotateAroundPoint(posOS, float3(0,0,0), trunkAxis, trunkWave);
                
                // ===== 2. BRANCH BENDING =====
                float branchBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
                float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchFlutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                
                float branchTime = time * branchSpeed;
                
                // Branch oscillation
                float branchAngle = sin(branchTime) * branchBend * strength * branchInfluence * trunkMask;
                
                // Add flutter for thin branches
                float flutter = sin(branchTime * 3.0 + phaseRand * 10.0) * branchFlutter * branchInfluence * strength;
                branchAngle += flutter;
                
                // Branch pivot at its base (height-based approximation)
                float3 branchPivot = float3(0, posAfterTrunk.y, 0);
                
                // Branch rotates around horizontal axis perpendicular to wind
                float3 branchAxis = normalize(cross(windDir, float3(0,1,0)));
                branchAxis = normalize(branchAxis + float3(0, 0.3, 0)); // Slight up tilt for natural look
                
                float3 posAfterBranch = RotateAroundPoint(posAfterTrunk, branchPivot, branchAxis, branchAngle);
                
                // Vertical sag for heavy branches
                posAfterBranch.y -= abs(branchAngle) * branchInfluence * 0.08;
                
                // ===== 3. CROWN (follows branch + shimmer) =====
                float crownFollow = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollow);
                float crownShimmer = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmer);
                float crownShimmerSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmerSpeed);
                
                // Crown inherits branch movement based on CrownFollow parameter
                float3 finalPos = posAfterBranch;
                
                if (crownInfluence > 0.01)
                {
                    // Follow branch movement (0 = no follow, 1 = full follow)
                    float3 branchMovement = posAfterBranch - posAfterTrunk;
                    finalPos = posAfterTrunk + branchMovement * crownFollow;
                    
                    // Add independent shimmer (using ORIGINAL position to avoid boiling)
                    float3 originalPos = posOS;
                    float noise1 = frac(dot(originalPos, float3(12.9898, 78.233, 45.5432)));
                    float noise2 = frac(dot(originalPos, float3(37.7193, 23.1415, 91.6734)));
                    
                    float shimmerXZ = sin(_Time.y * crownShimmerSpeed + noise1 * 20.0) * crownShimmer * crownInfluence * strength;
                    float shimmerY = cos(_Time.y * crownShimmerSpeed * 0.8 + noise2 * 15.0) * crownShimmer * 0.5 * crownInfluence * strength;
                    
                    // Shimmer affected by height (stronger at top)
                    float heightFactor = saturate(currentHeight / treeHeight);
                    shimmerXZ *= heightFactor;
                    shimmerY *= heightFactor;
                    
                    finalPos.xz += windDir.xz * shimmerXZ;
                    finalPos.y += shimmerY;
                }
                
                return finalPos;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                
                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color, v.normalOS);
                
                float4 posWS = mul(GetObjectToWorldMatrix(), float4(animatedPos, 1));
                o.positionWS = posWS.xyz;
                o.positionCS = TransformWorldToHClip(posWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                
                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;
                
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                
                return o;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                
                #ifdef _ALPHATEST_ON
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif
                
                float3 normalWS = normalize(IN.normalWS);
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float NdotL = saturate(dot(normalWS, mainLight.direction));
                float3 diffuse = mainLight.color * mainLight.shadowAttenuation * NdotL;
                float3 ambient = SampleSH(normalWS);
                
                col.rgb *= (diffuse + ambient);
                col.rgb = MixFog(col.rgb, IN.fogFactor);
                
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
            #pragma shader_feature _LEAN_ENABLED
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
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkStart)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkFalloff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownFollow)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmer)
                UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmerSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _LeanAmount)
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
            
            float3 RotateAroundPoint(float3 pos, float3 pivot, float3 axis, float angle)
            {
                float3 dir = pos - pivot;
                float c = cos(angle);
                float s = sin(angle);
                float dotAxis = dot(dir, axis);
                float3 crossAxis = cross(axis, dir);
                return pivot + dir * c + crossAxis * s + axis * dotAxis * (1 - c);
            }
            
            float GetHeightMask(float height, float treeH, float start, float falloff)
            {
                float raw = saturate((height - treeH * start) / max(0.001, treeH * falloff));
                return raw * raw * (3.0 - 2.0 * raw);
            }
            
            float3 ApplyWind(float3 posOS, float4 vColor, float3 normalOS)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif
                
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                float treeHeight = abs(GetObjectToWorldMatrix()._m13 - pivotWS.y);
                if (treeHeight < 0.01) treeHeight = 5.0;
                float currentHeight = max(0, worldPos.y - pivotWS.y);
                
                float branchInfluence = vColor.r;
                float crownInfluence = vColor.g;
                float phaseRand = vColor.b * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _PhaseRand);
                
                float speed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float strength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
                float time = _Time.y * speed + phase + phaseRand;
                
                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ)
                ));
                
                float trunkBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float trunkStart = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkStart);
                float trunkFalloff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkFalloff);
                
                float trunkMask = GetHeightMask(currentHeight, treeHeight, trunkStart, trunkFalloff);
                float trunkWave = sin(time * 0.8) * trunkBend * strength * trunkMask;
                
                #if defined(_LEAN_ENABLED)
                    float leanAmount = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeanAmount);
                    trunkWave += leanAmount * strength * trunkMask;
                #endif
                
                float3 trunkAxis = normalize(cross(float3(0,1,0), windDir));
                if (length(trunkAxis) < 0.01) trunkAxis = float3(1,0,0);
                float3 posAfterTrunk = RotateAroundPoint(posOS, float3(0,0,0), trunkAxis, trunkWave);
                
                float branchBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
                float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchFlutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                
                float branchTime = time * branchSpeed;
                float branchAngle = sin(branchTime) * branchBend * strength * branchInfluence * trunkMask;
                float flutter = sin(branchTime * 3.0 + phaseRand * 10.0) * branchFlutter * branchInfluence * strength;
                branchAngle += flutter;
                
                float3 branchPivot = float3(0, posAfterTrunk.y, 0);
                float3 branchAxis = normalize(cross(windDir, float3(0,1,0)));
                branchAxis = normalize(branchAxis + float3(0, 0.3, 0));
                
                float3 posAfterBranch = RotateAroundPoint(posAfterTrunk, branchPivot, branchAxis, branchAngle);
                posAfterBranch.y -= abs(branchAngle) * branchInfluence * 0.08;
                
                float crownFollow = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollow);
                float3 finalPos = posAfterBranch;
                
                if (crownInfluence > 0.01)
                {
                    float3 branchMovement = posAfterBranch - posAfterTrunk;
                    finalPos = posAfterTrunk + branchMovement * crownFollow;
                }
                
                return finalPos;
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
                float4 posWS = float4(TransformObjectToWorld(float4(animatedPos, 1)).xyz, 1);
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(posWS.xyz, normalWS, 0));
                
                return o;
            }
            
            half4 fragShadow(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                #ifdef _ALPHATEST_ON
                    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    half4 col = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif
                return 0;
            }
            ENDHLSL
        }
    }
    
    Fallback "Universal Render Pipeline/Lit"
}