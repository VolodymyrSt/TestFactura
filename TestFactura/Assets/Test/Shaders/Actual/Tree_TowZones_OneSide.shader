Shader "Custom/Tree_FullFeatures_VertexColor"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)

        [Header(Wind Settings)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        [Toggle(_LEAN_WIND)] _LeanIntoWind("Lean into Wind", Float) = 1.0
        _WindLeanWeight ("Wind Lean Static", Range(0, 1)) = 0.5
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0
        _WindSpeed ("Speed", Float) = 1
        _TreeHeight ("Tree Height Mask", Float) = 5.0
        _RootStiffness ("Root Stiffness", Range(0, 1)) = 0.2

        [Header(Zone Control)]
        _ZoneBoundaryZ ("Zone Boundary (Z axis)", Float) = 200.0
        _Zone1Strength ("Zone 1 Strength", Range(0, 2)) = 1.0
        _Zone2Strength ("Zone 2 Strength", Range(0, 2)) = 0.5
        
        [Header(Bending and Shimmer)]
        _TrunkBend ("Trunk Bend", Float) = 0.5
        _BranchFlutter ("Branch Flutter", Float) = 0.2
        _WindPhase ("Wind Phase", Float) = 0.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

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

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4, _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float, _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float, _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _RootStiffness)
                UNITY_DEFINE_INSTANCED_PROP(float, _ZoneBoundaryZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _Zone1Strength)
                UNITY_DEFINE_INSTANCED_PROP(float, _Zone2Strength)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindLeanWeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindPhase)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 vColor : COLOR; // Передаємо колір у фрагментний шейдер
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS,1)).xyz;
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                
                float treeH = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float stiffness = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootStiffness);
                float currentHeight = worldPos.y - pivotWS.y;
                float staticThreshold = treeH * stiffness;
                float mask = saturate((currentHeight - staticThreshold) / max(0.001, treeH - staticThreshold));
                float bendMask = mask * mask;

                float localZoneStrength = (pivotWS.z < UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ZoneBoundaryZ)) ? 
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Zone1Strength) : 
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Zone2Strength);

                float3 windDir = normalize(float3(UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0, UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ)) + 0.001);
                float time = (_Time.y * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed)) + UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);

                // --- ЛОГІКА НАХИЛУ ---
                float tBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);
                float trunkWave;

                #if defined(_LEAN_WIND)
                    float staticLean = tBend * leanWeight; 
                    float dynamicSway = sin(time + pivotWS.x * 0.5) * tBend * (1.0 - leanWeight);
                    
                    trunkWave = (staticLean + dynamicSway) * mask;
                #else
                    trunkWave = sin(time + pivotWS.x * 0.5) * tBend * mask;
                #endif

                // --- ЛИСТЯ (МЕРЕХТІННЯ) ---
                float bFlutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                float leafNoise = frac(dot(posOS.xyz, float3(12.9898, 78.233, 45.164)));
                
                float branchWave = sin(time * 2.5 + dot(worldPos.xyz, 0.5) + leafNoise) * bFlutter;
                float shimmer = sin(time * 12.0 + leafNoise * 10.0) * (bFlutter * 0.5);

                float finalLeafMotion = (branchWave + shimmer) * (vColor.g + vColor.b);

                // --- РЕЗУЛЬТАТ ---
                float totalWind = (trunkWave * bendMask + finalLeafMotion) * localZoneStrength;
                posOS.xz += windDir.xz * totalWind;
                posOS.y -= abs(totalWind) * 0.15 * bendMask; 

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                o.vColor = v.color; // Записуємо Vertex Color для frag
                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);
                
                o.positionHCS = TransformObjectToHClip(float4(animatedPos, 1));
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half4 baseCol = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                
                // ГОЛОВНА ЗМІНА: множимо на i.vColor
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * baseCol * i.vColor;
                
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(normalize(i.normalWS), mainLight.direction));
                half3 lighting = mainLight.color * (NdotL * 0.8 + 0.2);
                
                return half4(tex.rgb * lighting, tex.a);
            }
            ENDHLSL
        }
    }
}