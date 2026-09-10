Shader "Custom/ToonCel"
{
    Properties
    {
        [Header(Base)]
        _BaseColor      ("Base Color",      Color)      = (1,1,1,1)
        _BaseMap        ("Base Texture",    2D)         = "white" {}
        [Toggle(_ALPHATEST_ON)]
        _AlphaTest      ("Alpha Cutout",    Float)      = 0.0
        _Cutoff         ("Alpha Cutoff",    Range(0,1)) = 0.5

        [Header(Toon Ramp)]
        // Three light bands: shadow / mid / lit
        _ShadowColor    ("Shadow Color",    Color)      = (0.18, 0.12, 0.22, 1)
        _MidColor       ("Mid Color",       Color)      = (0.55, 0.45, 0.35, 1)
        _LitColor       ("Lit Color",       Color)      = (1,   0.95, 0.85, 1)
        _ShadowThresh   ("Shadow Threshold",Range(0,1)) = 0.2
        _MidThresh      ("Mid Threshold",   Range(0,1)) = 0.55
        _BandSmooth     ("Band Smoothness", Range(0,0.15)) = 0.02
        // Tint multiplies the ramp over the albedo
        _ToonTintStr    ("Ramp Tint Strength", Range(0,1)) = 0.85

        [Header(Specular)]
        [Toggle(_SPECULAR_ON)]
        _SpecularOn     ("Specular",        Float)      = 1.0
        _SpecColor      ("Specular Color",  Color)      = (1,1,1,1)
        _SpecSize       ("Specular Size",   Range(1,512)) = 64.0
        _SpecThresh     ("Specular Threshold", Range(0,1)) = 0.6
        _SpecSmooth     ("Specular Smooth", Range(0,0.1)) = 0.02

        [Header(Rim)]
        [Toggle(_RIM_ON)]
        _RimOn          ("Rim Light",       Float)      = 1.0
        _RimColor       ("Rim Color",       Color)      = (0.6, 0.8, 1.0, 1)
        _RimThresh      ("Rim Threshold",   Range(0,1)) = 0.55
        _RimSmooth      ("Rim Smoothness",  Range(0,0.2)) = 0.05
        _RimStr         ("Rim Strength",    Range(0,2)) = 0.8

        [Header(Outline)]
        [Toggle(_OUTLINE_ON)]
        _OutlineOn      ("Outline",         Float)      = 1.0
        _OutlineColor   ("Outline Color",   Color)      = (0.08, 0.05, 0.05, 1)
        _OutlineWidth   ("Outline Width",   Range(0,0.05)) = 0.008
        // Outline fades at distance (camera-space z)
        _OutlineDistFade ("Outline Dist Fade", Range(0,1)) = 0.3

        [Header(Ambient)]
        _AmbientColor   ("Ambient Color",   Color)      = (0.15, 0.18, 0.25, 1)
        _AmbientStr     ("Ambient Strength",Range(0,1)) = 0.4
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }

        // ═══════════════════════════════════════════════════════════════════
        // PASS 1 — Outline (inverted-hull, rendered first so it's under lit)
        // ═══════════════════════════════════════════════════════════════════
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On

            HLSLPROGRAM
            #pragma vertex   outlineVert
            #pragma fragment outlineFrag
            #pragma shader_feature _OUTLINE_ON
            #pragma shader_feature _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST, _BaseColor;
                float4 _OutlineColor;
                float  _OutlineWidth, _OutlineDistFade, _Cutoff;
                // (other properties declared but unused here — required for SRP batcher)
                float4 _ShadowColor, _MidColor, _LitColor;
                float  _ShadowThresh, _MidThresh, _BandSmooth, _ToonTintStr;
                float4 _SpecColor;
                float  _SpecSize, _SpecThresh, _SpecSmooth;
                float4 _RimColor;
                float  _RimThresh, _RimSmooth, _RimStr;
                float4 _AmbientColor;
                float  _AmbientStr;
            CBUFFER_END

            struct AttrOut { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct VaryOut { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; float outlineAlpha : TEXCOORD1; };

            VaryOut outlineVert(AttrOut IN)
            {
                VaryOut OUT;

                #if defined(_OUTLINE_ON)
                    // Scale outline width by distance so it stays consistent on screen
                    float3 posVS    = mul(UNITY_MATRIX_MV, float4(IN.positionOS.xyz, 1.0)).xyz;
                    float  distFade = 1.0 - saturate((-posVS.z) * _OutlineDistFade);
                    float  width    = _OutlineWidth * distFade;

                    float3 normalVS = mul((float3x3)UNITY_MATRIX_IT_MV, IN.normalOS);
                    normalVS.z      = 0.0;  // keep outline in screen plane — no depth distortion
                    normalVS        = normalize(normalVS);

                    posVS.xy       += normalVS.xy * width;
                    OUT.positionHCS = mul(UNITY_MATRIX_P, float4(posVS, 1.0));
                    OUT.outlineAlpha = distFade;
                #else
                    // If toggle off, collapse to clip-space origin — GPU culls degenerate triangles
                    OUT.positionHCS = float4(0,0,0,1);
                    OUT.outlineAlpha = 0;
                #endif

                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float4 outlineFrag(VaryOut IN) : SV_Target
            {
                #if defined(_ALPHATEST_ON)
                    float4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    clip(tex.a * _BaseColor.a - _Cutoff);
                #endif
                return float4(_OutlineColor.rgb, _OutlineColor.a * IN.outlineAlpha);
            }
            ENDHLSL
        }

        // ═══════════════════════════════════════════════════════════════════
        // PASS 2 — Lit cel-shading
        // ═══════════════════════════════════════════════════════════════════
        Pass
        {
            Name "ToonLit"
            Tags { "LightMode"="UniversalForward" "RenderType"="Opaque" "Queue"="Geometry" }
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _SPECULAR_ON
            #pragma shader_feature _RIM_ON
            #pragma shader_feature _OUTLINE_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST, _BaseColor;
                float4 _OutlineColor;
                float  _OutlineWidth, _OutlineDistFade, _Cutoff;
                float4 _ShadowColor, _MidColor, _LitColor;
                float  _ShadowThresh, _MidThresh, _BandSmooth, _ToonTintStr;
                float4 _SpecColor;
                float  _SpecSize, _SpecThresh, _SpecSmooth;
                float4 _RimColor;
                float  _RimThresh, _RimSmooth, _RimStr;
                float4 _AmbientColor;
                float  _AmbientStr;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
                float  fogFactor   : TEXCOORD4;
            };

            // Snaps a 0-1 value to a hard band edge with tiny smoothstep anti-alias
            float ToonStep(float threshold, float value, float smooth)
            {
                return smoothstep(threshold - smooth, threshold + smooth, value);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs  = GetVertexPositionInputs(IN.positionOS.xyz);
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
                // ── Albedo ─────────────────────────────────────────────────
                float4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                #if defined(_ALPHATEST_ON)
                    clip(albedo.a - _Cutoff);
                #endif

                float3 N = normalize(IN.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(IN.positionWS);

                // ── Main light + shadow ────────────────────────────────────
                Light mainLight = GetMainLight(IN.shadowCoord);
                float3 L        = normalize(mainLight.direction);
                float  shadow   = mainLight.shadowAttenuation;
                float  NdotL    = dot(N, L);

                // Shadow attenuates NdotL so toon bands respond to shadows
                float  toonNdotL = saturate(NdotL) * shadow;

                // ── Toon ramp: 3 bands ─────────────────────────────────────
                float inMid = ToonStep(_ShadowThresh, toonNdotL, _BandSmooth);
                float inLit = ToonStep(_MidThresh,    toonNdotL, _BandSmooth);

                float3 ramp = lerp(_ShadowColor.rgb,
                               lerp(_MidColor.rgb, _LitColor.rgb, inLit),
                               inMid);

                // Blend ramp with albedo
                float3 toonColor = lerp(albedo.rgb, albedo.rgb * ramp, _ToonTintStr);

                // ── Ambient ────────────────────────────────────────────────
                toonColor += _AmbientColor.rgb * _AmbientStr * albedo.rgb;

                // ── Specular (Blinn-Phong, hard threshold) ─────────────────
                #if defined(_SPECULAR_ON)
                {
                    float3 H        = normalize(L + V);
                    float  NdotH    = saturate(dot(N, H));
                    float  specular = pow(NdotH, _SpecSize);
                    float  specMask = ToonStep(_SpecThresh, specular, _SpecSmooth) * shadow;
                    // Specular only appears in lit band
                    specMask       *= inLit;
                    toonColor      += _SpecColor.rgb * specMask;
                }
                #endif

                // ── Rim light (Fresnel, hard threshold) ───────────────────
                #if defined(_RIM_ON)
                {
                    float  fresnel = 1.0 - saturate(dot(N, V));
                    float  rim     = ToonStep(_RimThresh, fresnel, _RimSmooth);
                    // Rim only on lit/mid side
                    rim           *= saturate(NdotL + 0.3);
                    toonColor     += _RimColor.rgb * rim * _RimStr;
                }
                #endif

                // ── Fog ───────────────────────────────────────────────────
                toonColor = MixFog(toonColor, IN.fogFactor);

                return float4(toonColor, albedo.a);
            }
            ENDHLSL
        }

        // ═══════════════════════════════════════════════════════════════════
        // PASS 3 — Shadow Caster
        // ═══════════════════════════════════════════════════════════════════
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back

            HLSLPROGRAM
            #pragma vertex   shadowVert
            #pragma fragment shadowFrag
            #pragma shader_feature _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST, _BaseColor;
                float4 _OutlineColor;
                float  _OutlineWidth, _OutlineDistFade, _Cutoff;
                float4 _ShadowColor, _MidColor, _LitColor;
                float  _ShadowThresh, _MidThresh, _BandSmooth, _ToonTintStr;
                float4 _SpecColor;
                float  _SpecSize, _SpecThresh, _SpecSmooth;
                float4 _RimColor;
                float  _RimThresh, _RimSmooth, _RimStr;
                float4 _AmbientColor;
                float  _AmbientStr;
            CBUFFER_END

            struct AttrS { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct VaryS { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; };

            VaryS shadowVert(AttrS IN)
            {
                VaryS OUT;
                float3 posWS  = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionHCS = TransformWorldToHClip(ApplyShadowBias(posWS, normWS, _MainLightPosition.xyz));
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float4 shadowFrag(VaryS IN) : SV_Target
            {
                #if defined(_ALPHATEST_ON)
                    float4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    clip(tex.a * _BaseColor.a - _Cutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }

        // ═══════════════════════════════════════════════════════════════════
        // PASS 4 — Depth/Normals (для Screen-Space effects, SSAO тощо)
        // ═══════════════════════════════════════════════════════════════════
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back

            HLSLPROGRAM
            #pragma vertex   dnVert
            #pragma fragment dnFrag
            #pragma shader_feature _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST, _BaseColor;
                float4 _OutlineColor;
                float  _OutlineWidth, _OutlineDistFade, _Cutoff;
                float4 _ShadowColor, _MidColor, _LitColor;
                float  _ShadowThresh, _MidThresh, _BandSmooth, _ToonTintStr;
                float4 _SpecColor;
                float  _SpecSize, _SpecThresh, _SpecSmooth;
                float4 _RimColor;
                float  _RimThresh, _RimSmooth, _RimStr;
                float4 _AmbientColor;
                float  _AmbientStr;
            CBUFFER_END

            struct AttrDN { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct VaryDN { float4 positionHCS : SV_POSITION; float3 normalWS : TEXCOORD0; float2 uv : TEXCOORD1; };

            VaryDN dnVert(AttrDN IN)
            {
                VaryDN OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float4 dnFrag(VaryDN IN) : SV_Target
            {
                #if defined(_ALPHATEST_ON)
                    float4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    clip(tex.a * _BaseColor.a - _Cutoff);
                #endif
                float3 n = normalize(IN.normalWS) * 0.5 + 0.5;
                return float4(n, 1.0);
            }
            ENDHLSL
        }
    }

    CustomEditor "UnityEditor.ShaderGUI"
}
