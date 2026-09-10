Shader "Custom/Tree_Wind_Procedural_Advanced"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Global Wind Direction)]
        _WindDirection ("Wind Direction (X, Z)", Vector) = (1, 0, 0.5, 0)

        [Header(Trunk Bend Settings)]
        _WindSpeed ("Trunk Speed", Float) = 1.5
        _WindStrength ("Trunk Strength", Float) = 0.2
        _TrunkLean ("Trunk Lean (Bending)", Range(0, 1)) = 0.15
        _TrunkFalloff ("Trunk Bend Curve (Pow)", Range(1, 3)) = 2.0

        [Header(Branch Noise Settings)]
        _BranchSpeed ("Branch Speed", Float) = 5.0
        _BranchSway ("Branch Sway Strength", Float) = 0.2
        _TreeRadiusThresh ("Min Tree Radius for Branches", Float) = 0.15
        _BranchFalloff ("Branch Mask Sharpness", Float) = 2.0

        [Header(Crown Shimmer Settings)]
        _CrownShimmer ("Crown Shimmer Amount", Range(0, 0.1)) = 0.03
        _CrownShimmerSpeed ("Crown Shimmer Speed", Float) = 7.0
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

        UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
            UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
            UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
            UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
            UNITY_DEFINE_INSTANCED_PROP(float4, _WindDirection)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
            UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkLean)
            UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkFalloff)
            UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
            UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSway)
            UNITY_DEFINE_INSTANCED_PROP(float,  _TreeRadiusThresh)
            UNITY_DEFINE_INSTANCED_PROP(float,  _BranchFalloff)
            UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmer)
            UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmerSpeed)
        UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

        // СПІЛЬНА ФУНКЦІЯ АНІМАЦІЇ ДЛЯ FORWARD LIT ТА SHADOW CASTER
        float3 ApplyProceduralWind(float3 posOS)
        {
            float time = _Time.y;

            // Отримуємо інстансовані змінні
            float4 windDirProp = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirection);
            float windSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
            float windStrength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
            float trunkLean = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkLean);
            float trunkFalloff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkFalloff);
            float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
            float branchSway = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSway);
            float radiusThresh = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeRadiusThresh);
            float branchFalloff = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFalloff);
            float crownShimmer = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmer);
            float crownShimmerSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmerSpeed);

            float3 originalPos = posOS;

            // Нормалізуємо напрямок вітру у площині XZ
            float2 windDir = normalize(windDirProp.xz);

            // 1. АВТОМАТИЧНА МАСКА СТОВБУРА (ЗА ВИСОТОЮ Y)
            float currentHeight = max(0.0, posOS.y); 
            float trunkMask = pow(currentHeight, trunkFalloff) * 0.05;

            // Розрахунок пориву вітру та ефекту Lean (постійний нахил у напрямку вітру)
            float windOscillation = sin(time * windSpeed);
            
            // Загальна сила зсуву стовбура = динамічні коливання + постійний нахил (Lean)
            float totalTrunkForce = (windOscillation * windStrength) + (trunkLean * (windOscillation * 0.3 + 0.7));
            
            // Зміщуємо стовбур строго вздовж обраного вектора вітру
            posOS.xz += windDir * (totalTrunkForce * trunkMask);

            // 2. АВТОМАТИЧНА МАСКА ДЛЯ ГІЛОК (ПЛАВНА)
            float currentRadius = length(originalPos.xz);
            float branchMask = saturate((currentRadius - radiusThresh) / max(0.01, currentRadius));
            branchMask = pow(branchMask, branchFalloff);

            // Коливання гілок робимо перпендикулярно та вздовж напрямку вітру для хаотичності
            float branchWave = sin(time * branchSpeed + originalPos.y * 3.0);
            float2 branchOffset = windDir * branchWave * branchSway;
            
            // Додаємо невелике бічне відхилення гілок (перпендикулярно вітру)
            float2 windPerp = float2(-windDir.y, windDir.x);
            branchOffset += windPerp * cos(time * (branchSpeed * 0.8) + originalPos.y) * (branchSway * 0.5);

            posOS.xz += branchOffset * branchMask;

            // 3. ОКРЕМА СУВОРІША МАСКА ДЛЯ КРОНИ (ШИМЕРУ)
            float crownRadiusThresh = radiusThresh * 2.0;
            float crownMaskRadius = saturate((currentRadius - crownRadiusThresh) / max(0.01, currentRadius));
            float crownMaskHeight = saturate(originalPos.y - 1.0); 
            float crownMask = pow(crownMaskRadius, 2.0) * crownMaskHeight;

            // Дрібне процедурне мерехтіння
            float noise = frac(sin(dot(originalPos, float3(12.9898, 78.233, 45.5432))) * 43758.5453);
            float shimmerTime = time * crownShimmerSpeed + noise * 20.0;
            
            float3 shimmerOffset;
            shimmerOffset.xz = windDir * sin(shimmerTime) * crownShimmer;
            shimmerOffset.y = cos(shimmerTime * 0.8) * crownShimmer * 0.6;

            posOS += shimmerOffset * crownMask;

            return posOS;
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float fogFactor    : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyProceduralWind(v.positionOS.xyz);
                o.positionCS = TransformObjectToHClip(animatedPos);
                
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

                clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));

                col.rgb = MixFog(col.rgb, IN.fogFactor);
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
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vertShadow(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyProceduralWind(v.positionOS.xyz);

                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                float4 posWS = float4(TransformObjectToWorld(float4(animatedPos, 1)).xyz, 1);
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(posWS.xyz, normalWS, 0));

                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;

                return o;
            }

            half4 fragShadow(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                return 0;
            }
            ENDHLSL
        }
    }
    Fallback "Universal Render Pipeline/Lit"
}