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
        _BranchBendFreq ("Branch Bend Frequency",Float) = 1.2

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
            "RenderType"  = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue"       = "Geometry"
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

            // ────────────────────────────────────────────
            //  PROPERTIES
            // ────────────────────────────────────────────
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

            // ────────────────────────────────────────────
            //  STRUCTS
            // ────────────────────────────────────────────
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;      // R=trunk  G=branch  B=crown/flutter
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float4 vertColor   : TEXCOORD3;
                float  fogFactor   : TEXCOORD4;
            };

            // ────────────────────────────────────────────
            //  HELPERS
            // ────────────────────────────────────────────

            // Плавна синусоїдальна хвиля (повертає -1..1)
            float WindSin(float phase, float speed, float freq)
            {
                return sin(_Time.y * speed + phase * freq);
            }

            // Два шари синусів для органічнішого руху
            float WindWave(float phase, float speed, float freq)
            {
                return WindSin(phase, speed, freq)
                     + 0.35 * WindSin(phase * 2.3 + 1.7, speed * 1.5, freq * 0.7);
            }

            // ────────────────────────────────────────────
            //  VERTEX
            // ────────────────────────────────────────────
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // ── читаємо маски з vertex color ──────
                float maskTrunk   = IN.color.r;   // червоний  → стовбур
                float maskBranch  = IN.color.b;   // синій   → гілки
                float maskFlutter = IN.color.g;   // зелений     → крона (flutter)

                // ── позиція у world space ─────────────
                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);

                // ── унікальна фаза кожного вертекса ───
                //    (щоб гілки не рухались синхронно)
                float phase = posWS.x * 0.7 + posWS.z * 0.4;

                // ────────────────────────────────────────
                // 1. TRUNK BEND
                //    Стовбур хитається як єдине ціле зверху.
                //    Сила зсуву пропорційна maskTrunk (R-канал):
                //      - знизу R≈0 → майже не рухається
                //      - зверху R≈1 → максимальний bend
                // ────────────────────────────────────────
                float2 windXZ = normalize(_WindDir.xz + float2(0.001, 0.0));
                float  trunkWave = WindWave(0.0, _TrunkBendSpeed, _TrunkBendFreq);

                float3 trunkOffset = float3(
                    windXZ.x * trunkWave * _TrunkBendAmt * maskTrunk,
                    0.0,
                    windXZ.y * trunkWave * _TrunkBendAmt * maskTrunk
                );

                // ────────────────────────────────────────
                // 2. BRANCH BEND
                //    Гілки мають власний bend (швидший, менший)
                //    АЛЕ також "успадковують" рух стовбура
                //    через trunkOffset * maskBranch.
                //
                //    Логіка:
                //      branchOffset  = власний рух гілки
                //      + trunkOffset * maskBranch   ← прив'язка до стовбура
                // ────────────────────────────────────────
                float branchWave = WindWave(phase, _BranchBendSpeed, _BranchBendFreq);

                float3 branchOffset = float3(
                    windXZ.x * branchWave * _BranchBendAmt * maskBranch,
                    0.0,
                    windXZ.y * branchWave * _BranchBendAmt * maskBranch
                );
                // Успадкування стовбурового руху
                branchOffset += trunkOffset * maskBranch;

                // ────────────────────────────────────────
                // 3. CROWN FLUTTER (мерехтіння)
                //    Висока частота, малі зсуви в усіх осях.
                //    Кожен вертекс має різну фазу → ефект
                //    "живого" тремтіння листя.
                // ────────────────────────────────────────
                float fx = WindSin(phase,              _FlutterSpeed,        _FlutterFreq);
                float fy = WindSin(phase * 1.3 + 0.9, _FlutterSpeed * 1.2,  _FlutterFreq * 1.5);
                float fz = WindSin(phase * 0.8 + 2.1, _FlutterSpeed * 0.9,  _FlutterFreq * 0.8);

                float3 flutterOffset = float3(fx, fy * 0.5, fz) * _FlutterAmt * maskFlutter;

                // ── також крона успадковує рух стовбура
                flutterOffset += trunkOffset * maskFlutter;

                // ────────────────────────────────────────
                // Фінальне зміщення
                // ────────────────────────────────────────
                float3 totalOffset = trunkOffset + branchOffset + flutterOffset;

                // Застосовуємо в object space
                float3 posOS_wind = IN.positionOS.xyz
                    + TransformWorldToObject(posWS + totalOffset)
                    - TransformWorldToObject(posWS);

                OUT.positionHCS = TransformObjectToHClip(posOS_wind);
                OUT.positionWS  = TransformObjectToWorld(posOS_wind);
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.vertColor   = IN.color;
                OUT.fogFactor   = ComputeFogFactor(OUT.positionHCS.z);

                return OUT;
            }

            // ────────────────────────────────────────────
            //  FRAGMENT
            // ────────────────────────────────────────────
            half4 frag(Varyings IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col      = texColor * _BaseColor;

                #ifdef _ALPHATEST_ON
                    clip(col.a - _Cutoff);
                #endif

                // Простий Lambert + ambient
                float3 nWS      = normalize(IN.normalWS);
                Light  mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float  NdotL    = saturate(dot(nWS, mainLight.direction));
                float3 diffuse  = mainLight.color * mainLight.shadowAttenuation * NdotL;
                float3 ambient  = SampleSH(nWS);

                col.rgb *= (diffuse + ambient);

                // Туман
                col.rgb = MixFog(col.rgb, IN.fogFactor);

                return col;
            }
            ENDHLSL
        }

        // Shadow caster pass
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
