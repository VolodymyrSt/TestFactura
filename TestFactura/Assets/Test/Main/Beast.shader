Shader "Custom/TreeWind"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        _WindStrength ("Wind Strength", Float) = 1.0
        _WindSpeed ("Wind Speed", Float) = 1.0
        _WindDirection ("Wind Direction", Vector) = (1,0,0,0)

        _TrunkBendStrength ("Trunk Bend Strength", Float) = 0.3
        _TrunkBendSpeed ("Trunk Bend Speed", Float) = 0.4

        _FlutterSpeed ("Flutter Speed", Float) = 8.0
        _FlutterStrength ("Flutter Strength", Float) = 0.05
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "TransparentCutout"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "AlphaTest"
        }

        Cull Off

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float  _Cutoff;

                float  _WindStrength;
                float  _WindSpeed;
                float4 _WindDirection;

                float  _TrunkBendStrength;
                float  _TrunkBendSpeed;

                float  _FlutterSpeed;
                float  _FlutterStrength;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;  // R=branch, G=foliage, B=phase, A=stiffness
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
                float4 fogFactor   : TEXCOORD4;
            };

            // -------------------------------------------------------
            // Плавне коливання — повертає значення від -1 до 1
            // -------------------------------------------------------
            float WindWave(float time, float speed, float phase)
            {
                return sin((time + phase) * speed);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // --- Розпакування vertex color ---
                float branchR    = IN.color.r;  // 0=основа гілки, 1=кінчик
                float foliageG   = IN.color.g;  // 0=стовбур, 1=краї листя
                float phaseB     = IN.color.b;  // унікальна фаза гілки
                float stiffnessA = IN.color.a;  // 1=жорстко, 0=м'яко
                float flexibility = 1.0 - stiffnessA;

                float t = _Time.y;
                float3 windDir = normalize(_WindDirection.xyz);

                // --- 1. ОСНОВНИЙ БЕНД ГІЛОК (канал R + A) ---
                // Хвиля зі зсувом фази для кожної гілки
                float wave = WindWave(t, _WindSpeed, phaseB * 6.2832);
                float bendAmt = wave * _WindStrength * branchR * flexibility;
                float3 bendOffset = windDir * bendAmt;

                // --- 2. НАХИЛ СТОВБУРА (незалежна повільна хвиля) ---
                // Стовбур нахиляється від середини — маска по висоті через A
                float trunkWave = WindWave(t, _TrunkBendSpeed, 0.0);
                // Висота вершини в object space — чим вище, тим більше нахил
                float heightMask = saturate(IN.positionOS.y / 3.0); // 3.0 = приблизна висота стовбура
                float trunkBend = trunkWave * _TrunkBendStrength * heightMask * stiffnessA;
                bendOffset += windDir * trunkBend;

                // --- 3. FLUTTER КРОНИ (канал G) ---
                // Окрема швидка хвиля тільки для листя
                float flutter = WindWave(t, _FlutterSpeed, phaseB * 3.14);
                // Перпендикулярний вектор для flutter (не вздовж вітру, а збоку)
                float3 flutterDir = float3(-windDir.z, windDir.y, windDir.x);
                float3 flutterOffset = flutterDir * flutter * _FlutterStrength * foliageG;

                // --- Підсумовуємо всі зміщення ---
                float3 finalOffset = bendOffset + flutterOffset;
                float4 positionOS = IN.positionOS + float4(finalOffset, 0.0);

                // --- Стандартний URP output ---
                VertexPositionInputs posInputs = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = normInputs.normalWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.shadowCoord = GetShadowCoord(posInputs);
                OUT.fogFactor   = ComputeFogFactor(posInputs.positionCS.z);

                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                float4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                // Alpha clip для листя
                clip(texColor.a - _Cutoff);

                // Просте освітлення
                InputData lightInput = (InputData)0;
                lightInput.positionWS     = IN.positionWS;
                lightInput.normalWS       = normalize(IN.normalWS);
                lightInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                lightInput.shadowCoord    = IN.shadowCoord;
                lightInput.fogCoord       = IN.fogFactor.x;

                SurfaceData surfData = (SurfaceData)0;
                surfData.albedo      = texColor.rgb;
                surfData.alpha       = texColor.a;
                surfData.smoothness  = 0.0;
                surfData.occlusion   = 1.0;

                float4 color = UniversalFragmentPBR(lightInput, surfData);
                color.rgb = max(color.rgb, texColor.rgb * 0.25); // мінімальна яскравість
                color.rgb = MixFog(color.rgb, IN.fogFactor.x);

                return color;
            }

            ENDHLSL
        }

        // Shadow caster pass — щоб дерево відкидало тінь
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex shadowVert
            #pragma fragment shadowFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float  _Cutoff;
                float  _WindStrength;
                float  _WindSpeed;
                float4 _WindDirection;
                float  _TrunkBendStrength;
                float  _TrunkBendSpeed;
                float  _FlutterSpeed;
                float  _FlutterStrength;
            CBUFFER_END

            struct AttrShadow
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
            };

            struct VaryShadow
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };

            float WindWave(float time, float speed, float phase)
            {
                return sin((time + phase) * speed);
            }

            VaryShadow shadowVert(AttrShadow IN)
            {
                VaryShadow OUT;

                float branchR    = IN.color.r;
                float foliageG   = IN.color.g;
                float phaseB     = IN.color.b;
                float stiffnessA = IN.color.a;
                float flexibility = 1.0 - stiffnessA;

                float t = _Time.y;
                float3 windDir = normalize(_WindDirection.xyz);

                float wave    = WindWave(t, _WindSpeed, phaseB * 6.2832);
                float bendAmt = wave * _WindStrength * branchR * flexibility;
                float3 bendOffset = windDir * bendAmt;

                float trunkWave  = WindWave(t, _TrunkBendSpeed, 0.0);
                float heightMask = saturate(IN.positionOS.y / 3.0);
                float trunkBend  = trunkWave * _TrunkBendStrength * heightMask ;
                bendOffset += windDir * trunkBend;

                float flutter = WindWave(t, _FlutterSpeed, phaseB * 3.14);
                float3 flutterDir = float3(-windDir.z, windDir.y, windDir.x);
                float3 flutterOffset = flutterDir * flutter * _FlutterStrength * foliageG;

                float3 posOS = IN.positionOS.xyz + bendOffset + flutterOffset;

                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float4 positionWS = float4(TransformObjectToWorld(posOS), 1.0);
                OUT.positionHCS = TransformWorldToHClip(ApplyShadowBias(positionWS.xyz, normalWS, _MainLightPosition.xyz));
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                return OUT;
            }

            float4 shadowFrag(VaryShadow IN) : SV_Target
            {
                float4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(texColor.a - _Cutoff);
                return 0;
            }

            ENDHLSL
        }
    }
}
