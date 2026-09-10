Shader "Custom/This"
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
        
        [Header(Lean)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind("Lean into Wind", Float) = 1.0
        _WindLeanWeight ("Wind Lean Static", Range(0, 1)) = 0.5
        
        [Header(Bend)]
        _TrunkBend ("Trunk Bend", Float) = 0.5
        _BranchFlutter ("Branch Flutter", Float) = 0.2
        _ShimmerIntensity ("Shimmer Intensity", Range(0, 2)) = 0.4
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

                UNITY_DEFINE_INSTANCED_PROP(float, _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindLeanWeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchFlutter)

                UNITY_DEFINE_INSTANCED_PROP(float, _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _RootStiffness)

                UNITY_DEFINE_INSTANCED_PROP(float, _WindPhase)
                UNITY_DEFINE_INSTANCED_PROP(float, _ShimmerIntensity)

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

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                float3 pivotWS  = GetObjectToWorldMatrix()._m03_m13_m23;

                float treeH     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float currentHeight = worldPos.y - pivotWS.y;

                // 1. Маска висоти (спільна для всього мешу)
                float mask = saturate(currentHeight / max(0.001, treeH));
                float bendMask = smoothstep(0.0, 1.0, mask);

                float wSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float time = (_Time.y * wSpeed) + phase;

                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX),
                    0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.001
                ));

                float tBend      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);
                float flutter    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);

                // --- ЛОГІКА ПЕРЕМИКАЧА LEAN ---
                float trunkSway;
                float swaySignal = sin(time); 

                #if defined(_LEAN_WIND)
                    // Якщо ГАЛОЧКА стоїть:
                    // Static Lean: постійне відхилення за вітром
                    float staticLean = tBend * leanWeight;
                    // Dynamic Sway: гойдання навколо точки нахилу
                    float dynamicSway = swaySignal * tBend * (1.0 - leanWeight);
                    
                    trunkSway = (staticLean + dynamicSway) * bendMask;
                #else
                    // Якщо ГАЛОЧКИ немає:
                    // Звичайне гойдання відносно центру (0)
                    trunkSway = swaySignal * tBend * bendMask;
                #endif

                // 2. Тремтіння листя (Green канал)
                float leafNoise = frac(dot(posOS.xyz, float3(12.9898, 78.233, 45.164)));
                float leafShimmer = sin(time * 5.0 + leafNoise * 10.0) * flutter * vColor.g;

                // 3. Фінальна комбінація
                // Ми додаємо рух листя до руху стовбура, щоб крона не відривалася
                float totalXZ = trunkSway + leafShimmer;

                // Застосовуємо зміщення по напрямку вітру
                posOS.xz += windDir.xz * totalXZ;

                // Корекція по Y (ефект "присідання" при сильному нахилі)
                posOS.y -= abs(trunkSway) * 0.1;

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

                float4 baseST =
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);

                o.uv =
                    v.uv * baseST.xy + baseST.zw;

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

                Light mainLight =
                    GetMainLight();

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