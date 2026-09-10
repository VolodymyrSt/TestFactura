Shader "Custom/Tree_Wind_VertexColor_Sequential"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Global Wind Direction)]
        _WindDirection ("Wind Direction (World Space X, Z)", Vector) = (1, 0, 0.5, 0)

        [Header(Trunk Bend Settings)]
        _WindSpeed ("Trunk Speed (Heavy)", Float) = 1.2
        _WindStrength ("Trunk Strength", Float) = 0.15
        _TrunkLean ("Trunk Lean (Bending)", Range(0, 1)) = 0.12
        _TrunkFalloff ("Trunk Bend Curve (Pow)", Range(1, 3)) = 2.0

        [Header(Branch Sway Settings)]
        _BranchSpeed ("Branch Speed (Fast)", Float) = 4.5
        _BranchSway ("Branch Sway Strength", Float) = 0.25

        [Header(Crown Shimmer Settings)]
        _CrownShimmer ("Crown Shimmer Amount", Range(0, 0.1)) = 0.02
        _CrownShimmerSpeed ("Crown Shimmer Speed", Float) = 8.0
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
            UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmer)
            UNITY_DEFINE_INSTANCED_PROP(float,  _CrownShimmerSpeed)
        UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)
        
        float2 Rotate2D(float2 pos, float angle)
        {
            float s, c;
            sincos(angle, s, c);
            return float2(pos.x * c - pos.y * s, pos.x * s + pos.y * c);
        }
        
        float3 ApplyVertexColorWind(float3 posOS, float4 vColor)
        {
            float time = _Time.y;
            
            float4 windDirProp    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirection);
            float windSpeed       = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
            float windStrength    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
            float trunkLean       = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkLean);
            float trunkFalloff    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkFalloff);
            float branchSpeed     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
            float branchSway      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSway);
            float crownShimmer    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmer);
            float crownShimmerSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownShimmerSpeed);

            float2 worldWindDir = normalize(float2(windDirProp.x, windDirProp.z) + 0.0001);

            // Маски
            float branchMask  = vColor.r;
            float crownMask   = vColor.g;
            float phaseOffset = vColor.b;
            float combinedBranchMask = max(branchMask, crownMask);

            // Позиція центру дерева у світі
            float3 worldOrigin = GetAbsolutePositionWS(TransformObjectToWorld(float3(0,0,0)));
            float objNoise = frac(sin(dot(worldOrigin.xz, float2(12.9898, 78.233))) * 43758.5453);

            // Переводимо базову модель у World Space ОДРАЗУ, щоб ротація об'єкта нічого не ламала
            float3 posWS = TransformObjectToWorld(posOS);

            // =======================================================
            // ПОСЛІДОВНІСТЬ 1: ШВИДКИЙ РУХ ГІЛОК (Навколо світової осі дерева)
            // =======================================================
            // Обертання робимо відносно світового центру дерева (worldOrigin.xz)
            float2 localXZ = posWS.xz - worldOrigin.xz;

            // Хак послідовності: Гілки легші, тому вони мають більшу швидкість (branchSpeed),
            // а також випереджають стовбур по фазі завдяки додаванню (time * branchSpeed)
            float branchTime = time * branchSpeed + phaseOffset * 6.0 + objNoise * 8.0 + (posWS.y * 0.5);
            float branchAngle = sin(branchTime) * branchSway * combinedBranchMask;
            
            localXZ = Rotate2D(localXZ, branchAngle);
            posWS.xz = localXZ + worldOrigin.xz;

            // Вертикальне тремтіння гілок у такт їхньому швидкому руху
            posWS.y += cos(branchTime * 0.8) * (branchSway * 0.15) * combinedBranchMask;

            // =======================================================
            // ПОСЛІДОВНІСТЬ 2: ПЛАВНИЙ, ІНЕРЦІЙНИЙ НАХИЛ СТОВБУРА
            // =======================================================
            // Висота дерева відносно його світового півоту
            float treeHeight = max(0.0, posWS.y - worldOrigin.y);
            float trunkMask = pow(treeHeight, trunkFalloff) * 0.05;

            // Стовбур важкий: швидкість менша (windSpeed). 
            // Додаємо віднімання фази (- 1.5), щоб створити запізнення (інерцію) відносно гілок
            float trunkTime = time * windSpeed + objNoise * 4.0 - 1.5;
            float windOscillation = sin(trunkTime);
            
            float totalTrunkForce = (windOscillation * windStrength) + (trunkLean * (windOscillation * 0.2 + 0.8));

            // Глобальний зсув усього мешу (стовбур + вже закручені гілки) за світовим вітром
            posWS.xz += worldWindDir * (totalTrunkForce * trunkMask);

            // =======================================================
            // ПОСЛІДОВНІСТЬ 3: МЕРЕХТІННЯ ЛИСТЯ (Супер-швидка мікро-фізика)
            // =======================================================
            float shimmerTime = time * crownShimmerSpeed + phaseOffset * 25.0 + objNoise * 12.0;
            posWS.xz += worldWindDir * sin(shimmerTime) * (crownShimmer * 0.4) * crownMask;
            posWS.y  += cos(shimmerTime * 0.9)          * (crownShimmer * 0.25) * crownMask;

            return posWS; 
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
                float4 color      : COLOR; 
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

                float3 animatedPosWS = ApplyVertexColorWind(v.positionOS.xyz, v.color);
                o.positionCS = TransformWorldToHClip(animatedPosWS);
                
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
                float4 color      : COLOR;
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

                float3 animatedPosWS = ApplyVertexColorWind(v.positionOS.xyz, v.color);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(animatedPosWS, normalWS, 0));

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