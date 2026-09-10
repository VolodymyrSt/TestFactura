Shader "Custom/TreeWind_URP"
{
    Properties
    {
        [Header(Base)]
        _BaseColor      ("Base Color",      Color)  = (1,1,1,1)
        _BaseMap        ("Albedo",          2D)     = "white" {}

        [Header(Wind Trunk)]
        _TrunkBendAmt   ("Trunk Bend Amount",   Float) = 0.15
        _TrunkBendSpeed ("Trunk Bend Speed",    Float) = 0.8
        _TrunkBendFreq  ("Trunk Bend Frequency",Float) = 0.5

        [Header(Wind Branch)]
        _BranchBendAmt  ("Branch Bend Amount",  Float) = 0.08
        _BranchBendSpeed("Branch Bend Speed",   Float) = 1.8
        _BranchBendFreq ("Branch Bend Freq",    Float) = 1.2

        [Header(Wind Flutter Crown)]
        _FlutterAmt     ("Flutter Amount",      Float) = 0.04
        _FlutterSpeed   ("Flutter Speed",       Float) = 8.0
        _FlutterFreq    ("Flutter Frequency",   Float) = 3.0

        [Header(Wind Direction)]
        _WindDir        ("Wind Direction XZ",   Vector) = (1, 0, 0.3, 0)

        [Header(Rendering)]
        [Toggle(_ALPHATEST_ON)] _AlphaClip ("Alpha Clip", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull", Float) = 2
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue"          = "Geometry"
        }

        Cull [_Cull]

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma shader_feature_local _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float  _TrunkBendAmt;
                float  _TrunkBendSpeed;
                float  _TrunkBendFreq;
                float  _BranchBendAmt;
                float  _BranchBendSpeed;
                float  _BranchBendFreq;
                float  _FlutterAmt;
                float  _FlutterSpeed;
                float  _FlutterFreq;
                float4 _WindDir;
                float  _Cutoff;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;

                // wind_mask — один атрибут, всі 4 канали:
                //   R = стовбур (trunk bend),   0=знизу .. 1=верхівка
                //   G = гілки   (branch bend),  0=біля стовбура .. 1=кінець
                //   B = крона   (flutter)
                //   A = pivot   (1=основа гілки, не рухається; 0=кінець, рухається)
                float4 color      : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float  fogFactor   : TEXCOORD3;
            };

            // ── два шари синусів = органічніший рух ──
            float WindWave(float phase, float speed, float freq)
            {
                return sin(_Time.y * speed + phase * freq)
                     + sin(_Time.y * speed * 1.5 + phase * freq * 0.7 + 1.7) * 0.35;
            }

            float WindSin(float phase, float speed, float freq)
            {
                return sin(_Time.y * speed + phase * freq);
            }

            Varyings vert(Attributes IN)
{
    Varyings OUT;

    // ------------------------------------------------
    // Vertex color masks
    // R = trunk
    // B = branches
    // G = crown/flutter
    // A = pivot
    // ------------------------------------------------
    float maskTrunk   = IN.color.r;
    float maskBranch  = IN.color.b;
    float maskFlutter = IN.color.g;
    float maskPivot   = IN.color.a;

    float pivotFactor = 1.0 - maskPivot;

    float3 posWS  = TransformObjectToWorld(IN.positionOS.xyz);

    float2 windXZ = normalize(_WindDir.xz + float2(0.001, 0.0));

    float phase = posWS.x * 0.7 + posWS.z * 0.4;

    // =========================================================
    // 1. TRUNK MOTION
    // =========================================================
    float trunkWave = WindWave(
        0.0,
        _TrunkBendSpeed,
        _TrunkBendFreq
    );

    float3 trunkOffset = float3(
        windXZ.x * trunkWave * _TrunkBendAmt * maskTrunk,
        0.0,
        windXZ.y * trunkWave * _TrunkBendAmt * maskTrunk
    );

    // =========================================================
    // 2. BRANCH MOTION
    // =========================================================
    float branchWave = WindWave(
        phase,
        _BranchBendSpeed,
        _BranchBendFreq
    );

    // чистий рух гілки
    float3 branchMotion = float3(
        windXZ.x * branchWave * _BranchBendAmt * pivotFactor,
        0.0,
        windXZ.y * branchWave * _BranchBendAmt * pivotFactor
    );

    // самі гілки
    float3 branchOffset = branchMotion * maskBranch;

    // гілки слідують за стовбуром
    branchOffset += trunkOffset * maskBranch;

    // =========================================================
    // 3. CROWN FOLLOW BRANCH
    // =========================================================
    // крона повторює рух гілки
    float3 crownFollowBranch = branchMotion * maskFlutter;

    // крона також слідує за стовбуром
    crownFollowBranch += trunkOffset * maskFlutter;

    // =========================================================
    // 4. FLUTTER
    // =========================================================
    float3 flutterOffset = float3(
        WindSin(
            phase,
            _FlutterSpeed,
            _FlutterFreq
        ),

        WindSin(
            phase * 1.3 + 0.9,
            _FlutterSpeed * 1.2,
            _FlutterFreq * 1.5
        ) * 0.5,

        WindSin(
            phase * 0.8 + 2.1,
            _FlutterSpeed * 0.9,
            _FlutterFreq * 0.8
        )
    ) * _FlutterAmt * maskFlutter;

    // =========================================================
    // FINAL OFFSET
    // =========================================================
    float3 totalOffset =
        trunkOffset +
        branchOffset +
        crownFollowBranch +
        flutterOffset;

    // world -> object delta
    float3 posOS_wind =
        IN.positionOS.xyz +
        TransformWorldToObject(posWS + totalOffset) -
        TransformWorldToObject(posWS);

    OUT.positionHCS = TransformObjectToHClip(posOS_wind);

    OUT.positionWS =
        TransformObjectToWorld(posOS_wind);

    OUT.normalWS =
        TransformObjectToWorldNormal(IN.normalOS);

    OUT.uv =
        TRANSFORM_TEX(IN.uv, _BaseMap);

    OUT.fogFactor =
        ComputeFogFactor(OUT.positionHCS.z);

    return OUT;
}
            half4 frag(Varyings IN) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                #ifdef _ALPHATEST_ON
                    clip(col.a - _Cutoff);
                #endif

                float3 nWS       = normalize(IN.normalWS);
                Light  mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float  NdotL     = saturate(dot(nWS, mainLight.direction));
                col.rgb *= mainLight.color * mainLight.shadowAttenuation * NdotL + SampleSH(nWS);
                col.rgb  = MixFog(col.rgb, IN.fogFactor);

                return col;
            }
            ENDHLSL
        }

        /*Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]
            HLSLPROGRAM
            #pragma vertex   vertShadow
            #pragma fragment fragShadow
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShadowCasterPass.hlsl"
            ENDHLSL
        }*/
    }

    FallBack "Universal Render Pipeline/Lit"
}
