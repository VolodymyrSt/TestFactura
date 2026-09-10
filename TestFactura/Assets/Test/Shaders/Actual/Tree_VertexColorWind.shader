// ============================================================================
//  Custom/Tree_VertexColorWind   (URP, HLSL)
//
//  Hierarchical, physically-motivated tree wind driven ENTIRELY by vertex color.
//  No world-height mask: a vertex moves ONLY where it is painted, so the base
//  (R=A=0) is always pinned. Works on any tree using this channel convention
//  (bare trunk+branches OR full crown), at any import scale.
//
//  Vertex color layout (measured from the FBX):
//    R = primary / trunk bend weight  (~0 at the base, ~1 toward the top & tips)
//    G = branch bend weight           (upper trunk + branches, 0 on rigid base)
//    B = tip / crown shimmer weight   (branch tips, leaves, finest geometry)
//    A = master weight                (~1 everywhere, ~0 at the very base)
//
//  Three layered motions, each gated by its channel:
//    1. TRUNK bend  : low-frequency arc, whole trunk leans from the base.
//    2. BRANCH bend : own faster wobble + a time-DELAYED copy of the trunk
//                     motion, so lighter branches trail / whip behind it.
//    3. TIP shimmer : fast, fine 3D flicker on tips & leaves.
//
//  Passes: ForwardLit + ShadowCaster + DepthOnly  (wind applied in all three,
//  so shadows and depth match the animated silhouette).
// ============================================================================
Shader "Custom/Tree_VertexColorWind"
{
    Properties
    {
        [MainTexture] _BaseMap      ("Albedo", 2D)                = "white" {}
        [MainColor]   _BaseColor    ("Tint", Color)              = (1,1,1,1)

        [Toggle(_ALPHATEST_ON)] _AlphaClip ("Alpha Clip (leaves)", Float) = 0
        _Cutoff       ("Alpha Cutoff", Range(0,1))               = 0.5

        [Header(Wind Global)]
        [Toggle(_USE_WIND_ON)] _UseWind ("Enable Wind", Float)   = 1
        _WindDirection ("Wind Direction (XZ)", Vector)           = (1,0,0,0)
        _WindStrength ("Wind Strength", Range(0,3))              = 1
        _WindSpeed    ("Wind Speed", Range(0,5))                 = 1
        _RootStiffness("Root Stiffness (pins more of R)", Range(0,0.95)) = 0.0

        [Header(Trunk Bend  (R channel))]
        _PrimaryStrength ("Trunk Bend (radians)", Range(0,0.4))   = 0.09
        _PrimaryFreq     ("Trunk Frequency", Range(0,4))          = 0.8

        [Header(Branch Bend  (G channel))]
        _BranchStrength ("Branch Bend (frac of height)", Range(0,0.3)) = 0.06
        _BranchFreq     ("Branch Frequency", Range(0,10))         = 2.2
        _BranchLag      ("Branch Lag (trail behind trunk, sec)", Range(0,1.5)) = 0.35

        [Header(Tip and Crown Shimmer  (B channel))]
        _LeafStrength ("Shimmer Amplitude (frac of height)", Range(0,0.2)) = 0.025
        _LeafFreq     ("Shimmer Frequency", Range(0,20))          = 6
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }
        LOD 200

        // -------------------------------------------------------------------
        //  Shared code: properties + the vertex-color wind function.
        // -------------------------------------------------------------------
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _Cutoff;
            float4 _WindDirection;
            float  _WindStrength;
            float  _WindSpeed;
            float  _RootStiffness;
            float  _PrimaryStrength;
            float  _PrimaryFreq;
            float  _BranchStrength;
            float  _BranchFreq;
            float  _BranchLag;
            float  _LeafStrength;
            float  _LeafFreq;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        // Returns the wind-displaced position in WORLD space.
        // All motion is weighted by the vertex color channels only.
        float3 ApplyVertexColorWind(float3 positionOS, float4 vColor)
        {
            float3 positionWS = TransformObjectToWorld(positionOS);

        #if !defined(_USE_WIND_ON)
            return positionWS;
        #endif

            float3 pivotWS         = GetObjectToWorldMatrix()._m03_m13_m23;
            float  heightAboveBase = positionWS.y - pivotWS.y;

            // ---- Weights straight from vertex color -----------------------
            // _RootStiffness re-maps R so more of the lower tree stays rigid,
            // but the gate is still 100% the painted color (never world height).
            float primW   = saturate((vColor.r - _RootStiffness) /
                                     max(1e-3, 1.0 - _RootStiffness)) * vColor.a;
            float branchW = vColor.g;
            float tipW    = vColor.b;

            // ---- Wind basis (horizontal) ----------------------------------
            float2 wd = _WindDirection.xy;
            wd = (dot(wd, wd) < 1e-6) ? float2(1, 0) : normalize(wd);
            float3 windDir  = float3(wd.x, 0, wd.y);
            float3 windSide = float3(-wd.y, 0, wd.x);

            float strength  = _WindStrength;
            float t         = _Time.y * _WindSpeed;
            float treePhase = pivotWS.x * 0.7 + pivotWS.z * 1.3;  // per-tree desync

            // Coherent gust envelope (slow swelling of the wind), shared by all bands.
            float gust = 0.65 + 0.35 * sin(t * 0.4 + treePhase);

            float3 offset = 0;

            // ---- 1) TRUNK BEND (R): low-freq arc, leans from the base ------
            //  Two detuned sines give a natural, non-repetitive sway; a small
            //  bias makes it rest slightly downwind. Amplitude grows with height
            //  (heightAboveBase) so the base stays put and the top leans most.
            float trunkOsc = sin(t * _PrimaryFreq + treePhase) * 0.8
                           + sin(t * _PrimaryFreq * 0.47 + treePhase * 1.7) * 0.2;
            float lean = _PrimaryStrength * strength * gust * (trunkOsc * 0.8 + 0.2) * primW;
            offset += windDir * (lean * heightAboveBase);
            offset.y -= 0.5 * (lean * lean) * heightAboveBase;       // arc keeps length

            // ---- 2) BRANCH BEND (G) with LAG: lighter branches trail --------
            //  Each branch wobbles at its own (faster) rate AND follows a time-
            //  delayed copy of the trunk motion -> it visibly lags / whips behind.
            float bPhase      = dot(positionWS, float3(0.30, 0.15, 0.30)) + treePhase;
            float ownOsc      = sin(t * _BranchFreq + bPhase);                    // light & fast
            float trailOsc    = sin((t - _BranchLag) * _PrimaryFreq + treePhase); // delayed trunk
            float branchDrive = ownOsc * 0.6 + trailOsc * 0.4;
            offset += (windDir * branchDrive + windSide * ownOsc * 0.35)
                    * (_BranchStrength * strength * gust * branchW * heightAboveBase);

            // ---- 3) TIP / CROWN SHIMMER (B): fast, fine, 3D flicker ---------
            float sPhase = dot(positionWS, float3(1.1, 1.3, 0.9));
            float shimA  = sin(t * _LeafFreq + sPhase);
            float shimB  = cos(t * _LeafFreq * 1.4 + sPhase * 1.7);
            offset += (windSide * shimA + windDir * shimA * 0.5 + float3(0, 1, 0) * shimB * 0.4)
                    * (_LeafStrength * strength * tipW * heightAboveBase);

            return positionWS + offset;
        }
        ENDHLSL

        // -------------------------------------------------------------------
        //  Forward lit
        // -------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _USE_WIND_ON
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float  fogCoord    : TEXCOORD3;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posWS  = ApplyVertexColorWind(v.positionOS.xyz, v.color);
                o.positionWS  = posWS;
                o.positionHCS = TransformWorldToHClip(posWS);
                o.normalWS    = TransformObjectToWorldNormal(v.normalOS);
                o.uv          = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogCoord    = ComputeFogFactor(o.positionHCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;
            #if defined(_ALPHATEST_ON)
                clip(tex.a - _Cutoff);
            #endif

                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half3 N     = normalize(i.normalWS);
                half  NdotL = saturate(dot(N, mainLight.direction));
                half3 diffuse = mainLight.color * (NdotL * mainLight.shadowAttenuation);
                half3 ambient = SampleSH(N);

                half3 color = tex.rgb * (diffuse + ambient);
                color = MixFog(color, i.fogCoord);
                return half4(color, tex.a);
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        //  Shadow caster (wind applied so shadows match)
        // -------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex shadowVert
            #pragma fragment shadowFrag
            #pragma shader_feature_local _USE_WIND_ON
            #pragma shader_feature_local _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };

            Varyings shadowVert(Attributes v)
            {
                Varyings o;
                float3 posWS    = ApplyVertexColorWind(v.positionOS.xyz, v.color);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

                float4 positionCS = TransformWorldToHClip(
                    ApplyShadowBias(posWS, normalWS, _LightDirection));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                o.positionHCS = positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            half4 shadowFrag(Varyings i) : SV_Target
            {
            #if defined(_ALPHATEST_ON)
                half a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).a * _BaseColor.a;
                clip(a - _Cutoff);
            #endif
                return 0;
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        //  Depth only (wind applied so depth prepass matches)
        // -------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex depthVert
            #pragma fragment depthFrag
            #pragma shader_feature_local _USE_WIND_ON
            #pragma shader_feature_local _ALPHATEST_ON

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };

            Varyings depthVert(Attributes v)
            {
                Varyings o;
                float3 posWS  = ApplyVertexColorWind(v.positionOS.xyz, v.color);
                o.positionHCS = TransformWorldToHClip(posWS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            half4 depthFrag(Varyings i) : SV_Target
            {
            #if defined(_ALPHATEST_ON)
                half a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).a * _BaseColor.a;
                clip(a - _Cutoff);
            #endif
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
