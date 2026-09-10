Shader "Custom/Tree_TwoZones_Wind_Instanced"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)


        [Header(Wind Settings)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0
        _WindSpeed ("Speed", Float) = 1
        _TreeHeight ("Tree Height Mask", Float) = 5.0
        _TrunkBend ("Trunk Bend", Float) = 0.5
        _BranchFlutter ("Branch Flutter", Float) = 0.2


        [Header(Zone Control)]
        _ZoneBoundaryZ ("Zone Boundary (Z axis)", Float) = 200.0
        _Zone1Strength ("Zone 1 Strength", Range(0, 2)) = 1.0
        _Zone2Strength ("Zone 2 Strength", Range(0, 2)) = 0.5
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


            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);


            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4, _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float, _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float, _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _ZoneBoundaryZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _Zone1Strength)
                UNITY_DEFINE_INSTANCED_PROP(float, _Zone2Strength)
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
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };


            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1)).xyz;
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;

                float treeH = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float currentHeight = worldPos.y - pivotWS.y;

                float h = saturate(currentHeight / max(0.001, treeH));
                float heightMask = smoothstep(0.0, 1.0, h);
                float bendMask = heightMask * heightMask;

                float boundaryZ = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ZoneBoundaryZ);
                float z1Str = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Zone1Strength);
                float z2Str = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Zone2Strength);
                float localZoneStrength = (pivotWS.z < boundaryZ) ? z1Str : z2Str;

                float wX = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX);
                float wZ = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ);
                float3 windDir = normalize(float3(wX, 0, wZ) + 0.001);

                float wSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float time = (_Time.y * wSpeed) + phase;

                float tBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float bFlutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);

                float bendWeight = vColor.r;
                float branchWeight = vColor.g;
                float noiseWeight = vColor.b;

                // 1. Основний вигин стовбура (повільний)
                float mainBend = sin(time + pivotWS.x * 0.35 + pivotWS.z * 0.25) * tBend * bendMask * bendWeight;

                // 2. Рух великих гілок (середній)
                float branchMotion = sin(time * 1.7 + worldPos.y * 0.8 + worldPos.x * 0.3) * bFlutter * branchWeight * heightMask;

                // 3. Додатковий хаотичний шум
                float noiseMotion = sin(time * 3.2 + dot(worldPos.xyz, float3(1.7, 2.3, 1.1))) * bFlutter * 0.5 * noiseWeight;

                // --- НОВИЙ БЛОК: МЕРЕХТІННЯ (SHIMMER) ---
                // Використовуємо високу швидкість (time * 10.0) та індивідуальні координати для "тремтіння" листя
                float shimmerSpeed = time * 12.0; 
                float leafIndividualNoise = frac(dot(posOS.xyz, float3(12.989, 78.233, 45.164)));
                
                float shimmerMotion = sin(shimmerSpeed + leafIndividualNoise * 20.0) 
                                    * (bFlutter * 0.4) // амплітуда мерехтіння
                                    * (branchWeight + noiseWeight) // тільки там, де листя
                                    * heightMask;
                // ----------------------------------------

                float totalWind = (mainBend + branchMotion + noiseMotion + shimmerMotion) * localZoneStrength;

                // Зміщення по горизонталі
                posOS.xz += windDir.xz * totalWind;

                // Додаємо трохи вертикального "підстрибування" для мерехтіння
                posOS.y += shimmerMotion * 0.5;

                return posOS;
            }


            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);


                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);
                o.positionHCS = TransformObjectToHClip(float4(animatedPos, 1));


                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;


                o.normalWS = TransformObjectToWorldNormal(v.normalOS);


                return o;
            }


            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);


                half4 baseCol = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * baseCol;


                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(normalize(i.normalWS), mainLight.direction));
                half3 lighting = mainLight.color * (NdotL * 0.8 + 0.2);


                return half4(tex.rgb * lighting, tex.a);
            }


            ENDHLSL
        }
    }
}
