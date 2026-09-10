Shader "Custom/Tree_Wind_Final_Absolute"
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
        
        [Header(Bend)]
        _TrunkBend ("Trunk/Branch Bend", Float) = 0.5
        _LeafFlutter ("Leaf Flutter Intensity", Float) = 0.15
        _ShimmerSpeed ("Shimmer Speed", Range(0, 10)) = 5.0
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
                UNITY_DEFINE_INSTANCED_PROP(float, _LeafFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float, _ShimmerSpeed)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR; 
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                
                float wSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float time = _Time.y * wSpeed;

                float3 windDir = normalize(float3(
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.0001));

                float tBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float flutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeafFlutter);
                float sSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ShimmerSpeed);

                // --- 1. ГЛОБАЛЬНЕ КОЛИВАННЯ (R канал) ---
                // Однакове для всього дерева, щоб деталі не відривалися.
                float sway = sin(time + pivotWS.x * 0.5 + pivotWS.z * 0.5);
                float mainMove = sway * tBend * vColor.r;

                // --- 2. ЛОКАЛЬНЕ ТРЕМТІННЯ ЛИСТЯ (G канал) ---
                // Додається ПОВЕРХ основного руху.
                // Використовуємо frac від координат, щоб кожна купка листя мала свій офсет
                float leafNoise = frac(dot(posOS.xyz, float3(12.9898, 78.233, 45.164)));
                float leafSway = sin(time * sSpeed + leafNoise * 10.0) * flutter * vColor.g;

                // Розраховуємо фінальне зміщення
                // Важливо: mainMove впливає на ВСЕ, де R > 0. 
                // leafSway додає дрібну вібрацію тільки там, де G > 0.
                float3 offset = windDir * (mainMove + leafSway);

                posOS.xyz += offset;

                // Корекція висоти (Y), щоб дерево не розтягувалося, а гнулося по дузі
                posOS.y -= length(offset.xz) * 0.15 * vColor.r;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);
                
                o.positionWS = mul(GetObjectToWorldMatrix(), float4(animatedPos, 1)).xyz;
                o.positionHCS = TransformWorldToHClip(o.positionWS);

                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;

                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                float3 dx = ddx(i.positionWS);
                float3 dy = ddy(i.positionWS);
                float3 normalWS = normalize(cross(dy, dx));

                half4 baseCol = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                Light mainLight = GetMainLight();
                float NdotL = saturate(dot(normalWS, mainLight.direction));
                float3 lighting = mainLight.color * (NdotL + 0.3);

                return half4(tex.rgb * baseCol.rgb * lighting, tex.a);
            }
            ENDHLSL
        }
    }
}