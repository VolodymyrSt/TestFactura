Shader "Custom/Tree_Wind_Instanced_v3"
{
    Properties
    {
        _BaseMap  ("Albedo",       2D)          = "white" {}
        _BaseColor("Global Color", Color)       = (1,1,1,1)
        _Cutoff   ("Alpha Cutoff", Range(0,1))  = 0.5

        [Header(Wind Toggle)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0

        [Header(Wind Direction and Speed)]
        _WindSpeed ("Wind Speed",  Float)       = 1.0
        _WindDirX  ("Wind Dir X",  Range(-1,1)) = 1.0
        _WindDirZ  ("Wind Dir Z",  Range(-1,1)) = 0.0

        [Header(Root Stiffness)]
        _TreeHeight  ("Tree Height",         Float)          = 5.0
        _RootStart   ("Root Stiff Start",    Range(0,1))     = 0.15
        _RootFalloff ("Root Falloff Width",  Range(0.01,1))  = 0.25

        [Header(Static Lean)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind("Lean into Wind", Float) = 1.0
        _WindLeanWeight("Wind Lean Static", Range(0,1)) = 0.4

        [Header(Trunk)]
        _TrunkBend("Trunk Bend Angle", Float) = 0.08

        [Header(Branch)]
        // Vertex color B = branch weight (0=стовбур, 1=кінчик гілки)
        _BranchBend  ("Branch Bend Angle",  Float) = 0.12
        _BranchSpeed ("Branch Speed",       Float) = 1.3
        _BranchPhase ("Branch Phase Offset",Float) = 0.7

        [Header(Crown)]
        // Vertex color G = crown weight (0=деревина, 1=листя)
        _CrownFlutter       ("Crown Flutter",         Range(0,0.08)) = 0.02
        _CrownFollowStrength("Crown Follow Strength", Range(0,1))    = 0.6

        [HideInInspector] _WindPhase("", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "TransparentCutout"
            "Queue"          = "AlphaTest"
            "RenderPipeline" = "UniversalPipeline"
        }

        // ══════════════════════════════════════════════════════════════════
        // HLSLINCLUDE — спільний для всіх Pass
        // ══════════════════════════════════════════════════════════════════
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

        UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
            UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
            UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
            UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirX)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirZ)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
            UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindLeanWeight)
            UNITY_DEFINE_INSTANCED_PROP(float,  _BranchBend)
            UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
            UNITY_DEFINE_INSTANCED_PROP(float,  _BranchPhase)
            UNITY_DEFINE_INSTANCED_PROP(float,  _CrownFlutter)
            UNITY_DEFINE_INSTANCED_PROP(float,  _CrownFollowStrength)
            UNITY_DEFINE_INSTANCED_PROP(float,  _TreeHeight)
            UNITY_DEFINE_INSTANCED_PROP(float,  _RootStart)
            UNITY_DEFINE_INSTANCED_PROP(float,  _RootFalloff)
            UNITY_DEFINE_INSTANCED_PROP(float,  _WindPhase)
        UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

        // ──────────────────────────────────────────────────────────────────
        // Rodrigues rotation
        // ──────────────────────────────────────────────────────────────────
        float3 RotateAroundAxis(float3 v, float3 axis, float angle)
        {
            float s, c;
            sincos(angle, s, c);
            return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
        }

        // ──────────────────────────────────────────────────────────────────
        // Cubic-smooth height mask   0=корінь (нерухомо)  1=верхівка
        // ──────────────────────────────────────────────────────────────────
        float HeightMask(float h, float treeH, float rootStart, float rootFalloff)
        {
            float raw = saturate((h - treeH * rootStart) / max(0.001, treeH * rootFalloff));
            return raw * raw * (3.0 - 2.0 * raw);   // smoothstep cubic
        }

        // ──────────────────────────────────────────────────────────────────
        // VERTEX COLOR СЕМАНТИКА (як профарбовано):
        //
        //   vColor.b  — branch weight
        //               0 = стовбур / основа гілки
        //               1 = кінчик гілки
        //               (синій колір у Blender = повний синій → b=1.0)
        //
        //   vColor.g  — crown weight
        //               0 = деревина
        //               1 = листя / крона
        //               (зелений колір у Blender → g=1.0)
        //
        //   vColor.r  — НЕ використовується (червоний)
        //
        //   Стовбур   — r=0, g=0, b=0  (чорний / без кольору)
        //
        // ──────────────────────────────────────────────────────────────────

        // ──────────────────────────────────────────────────────────────────
        // ApplyWind — повертає анімовану позицію та нормаль
        // ──────────────────────────────────────────────────────────────────
        void ApplyWind(
            float3  posOS,
            float3  normalOS,
            float4  vColor,
            out float3 outPos,
            out float3 outNorm)
        {
            outPos  = posOS;
            outNorm = normalOS;

            #if !defined(_USE_WIND_ON)
                return;
            #endif

            // ── Props ─────────────────────────────────────────────────────
            float treeH      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
            float rootStart  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootStart);
            float rootFall   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _RootFalloff);
            float wSpeed     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
            float phase      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
            float tBend      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
            float leanW      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindLeanWeight);
            float brBend     = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchBend);
            float brSpeed    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
            float brPhase    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchPhase);
            float crFlutter  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFlutter);
            float crFollow   = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _CrownFollowStrength);

            // ── Vertex color weights ──────────────────────────────────────
            // Синій канал = гілки
            float branchW = vColor.b;
            // Зелений канал = крона
            float crownW  = vColor.g;
            // Стовбур = де обидва близько до нуля

            // ── Smooth height mask ────────────────────────────────────────
            // posOS.y = висота у object space (pivot = корінь дерева)
            float mask = HeightMask(posOS.y, treeH, rootStart, rootFall);

            // ── Wind direction & rotation axis ────────────────────────────
            float3 windDir = normalize(float3(
                UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX), 0.0,
                UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.001));

            // Вісь обертання перпендикулярна до вітру у XZ-площині
            float3 windAxis = normalize(float3(-windDir.z, 0.0, windDir.x));

            // ── Час ──────────────────────────────────────────────────────
            float trunkTime  = _Time.y * wSpeed + phase;
            float branchTime = _Time.y * brSpeed + phase + brPhase;

            // Per-vertex pseudo-random phase через hash позиції
            // (не через vertex color — економимо канали)
            float vRand = frac(dot(posOS, float3(12.9898, 78.233, 45.164)));

            float3 p = posOS;
            float3 n = normalOS;

            // ═════════════════════════════════════════════════════════════
            // 1. TRUNK — rotation навколо кореня (0,0,0)
            //    Застосовується до ВСІХ вершин (стовбур + гілки + крона)
            //    як базовий рух усього дерева
            // ═════════════════════════════════════════════════════════════
            float trunkSin = sin(trunkTime);

            float trunkAngle;
            #if defined(_LEAN_WIND)
                trunkAngle = (tBend * leanW + trunkSin * tBend * (1.0 - leanW)) * mask;
            #else
                trunkAngle = trunkSin * tBend * mask;
            #endif

            p = RotateAroundAxis(p, windAxis, trunkAngle);
            n = RotateAroundAxis(n, windAxis, trunkAngle);

            // ═════════════════════════════════════════════════════════════
            // 2. BRANCH — rotation навколо pivot гілки
            //    Тільки для вершин де vColor.b > 0
            //
            //    branchPivot = проекція на Y-вісь стовбура після trunk rotation
            //    Апроксимація: гілки виходять зі стовбура горизонтально,
            //    тому pivot = (0, p.y, 0)
            // ═════════════════════════════════════════════════════════════
            [branch]
            if (branchW > 0.001)
            {
                float3 branchPivot = float3(0.0, p.y, 0.0);
                float3 local       = p - branchPivot;

                // Кут: branchW дає плавний градієнт від основи до кінчика
                // mask: нижні гілки рухаються менше
                // vRand: невелика варіація фази між вершинами
                float brSin    = sin(branchTime + vRand * 1.5);
                float brAngle  = brSin * brBend * branchW * mask;

                local = RotateAroundAxis(local, windAxis, brAngle);
                p = branchPivot + local;
                n = RotateAroundAxis(n, windAxis, brAngle * branchW);
            }

            // ═════════════════════════════════════════════════════════════
            // 3. CROWN — tiny shimmer + follow за гілкою
            //    Тільки для вершин де vColor.g > 0
            //
            //    НЕ робимо сильний flutter — крона це великі welded slabs.
            //    Основний рух = inheritance від branch через crownFollow.
            //    Shimmer = 0.01..0.03 щоб не було желе.
            // ═════════════════════════════════════════════════════════════
            [branch]
            if (crownW > 0.001)
            {
                // Tiny shimmer — дуже малий, лише видимість живого листя
                float shimmer = sin(trunkTime * 11.0 + vRand * 17.0)
                                * crFlutter * crownW * mask;
                p += windDir * shimmer;

                // Crown follow — крона повторює рух гілки з невеликою затримкою
                // Pivot аналогічно до гілки
                float3 crPivot = float3(0.0, p.y, 0.0);
                float3 localC  = p - crPivot;

                float followAngle = sin(branchTime - 0.25 + vRand * 1.2)
                                    * brBend * crFollow * crownW * mask;

                localC = RotateAroundAxis(localC, windAxis, followAngle);
                p      = crPivot + localC;
                n      = RotateAroundAxis(n, windAxis, followAngle * crownW);
            }

            outPos  = p;
            outNorm = normalize(n);
        }

        ENDHLSL

        // ══════════════════════════════════════════════════════════════════
        // FORWARD LIT
        // ══════════════════════════════════════════════════════════════════
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature _USE_WIND_ON
            #pragma shader_feature _LEAN_WIND
            #pragma shader_feature _ALPHATEST_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
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
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float  fogFactor   : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animPos, animNorm;
                ApplyWind(v.positionOS.xyz, v.normalOS, v.color, animPos, animNorm);

                o.positionHCS = TransformObjectToHClip(float4(animPos, 1.0));
                o.positionWS  = TransformObjectToWorld(float4(animPos, 1.0)).xyz;
                o.normalWS    = TransformObjectToWorldNormal(animNorm);  // анімована нормаль
                o.fogFactor   = ComputeFogFactor(o.positionHCS.z);

                float4 st = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * st.xy + st.zw;

                return o;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col      = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);

                #ifdef _ALPHATEST_ON
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif

                float3 nWS       = normalize(IN.normalWS);
                Light  mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float  NdotL     = saturate(dot(nWS, mainLight.direction));
                float3 diffuse   = mainLight.color * mainLight.shadowAttenuation * NdotL;
                float3 ambient   = SampleSH(nWS);

                col.rgb *= (diffuse + ambient);
                col.rgb  = MixFog(col.rgb, IN.fogFactor);

                return col;
            }

            ENDHLSL
        }

        // ══════════════════════════════════════════════════════════════════
        // SHADOW CASTER — та сама ApplyWind, тіні не плавають
        // ══════════════════════════════════════════════════════════════════
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex   vertShadow
            #pragma fragment fragShadow
            #pragma shader_feature _USE_WIND_ON
            #pragma shader_feature _LEAN_WIND
            #pragma shader_feature _ALPHATEST_ON
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
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vertShadow(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animPos, animNorm;
                ApplyWind(v.positionOS.xyz, v.normalOS, v.color, animPos, animNorm);

                float3 normalWS = TransformObjectToWorldNormal(animNorm);
                float3 posWS    = TransformObjectToWorld(float4(animPos, 1.0)).xyz;
                o.positionHCS   = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, 0));

                float4 st = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * st.xy + st.zw;

                return o;
            }

            half4 fragShadow(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                #ifdef _ALPHATEST_ON
                    half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    half4 col = tex * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                    clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                #endif
                return 0;
            }

            ENDHLSL
        }
    }
}
