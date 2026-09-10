Shader "Custom/TreeWind3Channel_Enhanced"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Wind)]
        _WindDirection ("Wind Direction (XYZ)", Vector) = (1,0,0,0)
        _WindSpeed ("Wind Speed", Float) = 1.0
        _BranchLeadTime ("Branch Lead Time (sec)", Float) = 0.5

        [Header(Lean)]
        [Toggle(_LEAN_WIND)]  _LeanIntoWind ("Lean into Wind", Float) = 1.0
        _WindLean ("Wind Lean Bias", Range(0,1)) = 0.3
        [Toggle(_POLAR_LEAN)] _PolarLean ("Polar Lean (XZ axes)", Float) = 1.0

        [Header(Trunk)]
        _TrunkStrength          ("Trunk Strength",        Float)       = 0.3
        _TrunkSpeed             ("Trunk Speed",           Float)       = 0.5
        _TrunkHeight            ("Trunk Height",          Float)       = 5.0
        _TrunkSecondaryStrength ("Secondary Sway",        Range(0,1))  = 0.25
        _TrunkSecondarySpeed    ("Secondary Sway Speed",  Float)       = 1.3

        [Header(Branches)]
        _BranchStrength      ("Branch Strength",       Float)          = 0.4
        _BranchSpeed         ("Branch Speed",          Float)          = 0.5
        _BranchPhaseVariance ("Branch Phase Variance", Range(0,6.28))  = 1.5

        [Header(Flutter)]
        _FlutterStrength  ("Flutter Strength",  Float)       = 0.02
        _FlutterSpeed     ("Flutter Speed",     Float)       = 8.0
        _FlutterVertical  ("Flutter Vertical",  Range(0,1))  = 0.4
        _FlutterVariance  ("Flutter Variance",  Range(0,1))  = 0.6

        [Header(Turbulence)]
        _TurbulenceStrength ("Turbulence Strength", Float) = 0.15
        _TurbulenceSpeed    ("Turbulence Speed",    Float) = 2.5
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }
        Cull Off

        // ─────────────────────────────────────────────────────────────────────
        // Shared wind logic — compiled once, used by both passes
        // ─────────────────────────────────────────────────────────────────────
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST, _BaseColor, _WindDirection;
            float  _Cutoff, _WindSpeed, _BranchLeadTime;
            float  _WindLean;
            float  _TrunkStrength, _TrunkSpeed, _TrunkHeight;
            float  _TrunkSecondaryStrength, _TrunkSecondarySpeed;
            float  _BranchStrength, _BranchSpeed, _BranchPhaseVariance;
            float  _FlutterStrength, _FlutterSpeed;
            float  _FlutterVertical, _FlutterVariance;
            float  _TurbulenceStrength, _TurbulenceSpeed;
        CBUFFER_END

        // Rodrigues rotation around arbitrary axis
        float3 RotateAroundAxis(float3 p, float3 axis, float angle)
        {
            float s = sin(angle), c = cos(angle);
            return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
        }

        // Cheap positional hash — per-vertex unique values without a texture
        float PosHash(float3 p)
        {
            return frac(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
        }

        // Two-layer pseudo-turbulence (no texture needed)
        float Turbulence(float3 pos, float t)
        {
            float a = sin(t * _TurbulenceSpeed       + pos.x * 0.7 + pos.z * 0.3);
            float b = sin(t * _TurbulenceSpeed * 1.618 + pos.z * 0.5 - pos.y * 0.2);
            return a * b;
        }

        // ── Main wind displacement ──────────────────────────────────────────
        // Call this from every vertex shader; #if keywords resolved per-variant.
        float3 WindDisplace(float3 posOS, float4 vertColor, float3 objWorldPos)
        {
            float t        = _Time.y;
            float moveR    = vertColor.r;   // bend weight
            float flutterG = vertColor.g;   // flutter weight
            float isBranch = vertColor.b;   // 1 = branch/crown vertex

            // ── Freeze rest-pose position for all hash/distance lookups ────
            // CRITICAL: hashes and lateral distances must never be computed
            // from a transformed posOS — that changes every frame and causes
            // flickering.  posRest stays constant for the lifetime of a vertex.
            float3 posRest = posOS;

            // Flatten wind to XZ so vertical wind components don't tilt the bend axis
            float3 windDir   = normalize(_WindDirection.xyz);
            float3 windDir2D = normalize(float3(windDir.x, 0.0, windDir.z));

            // Primary axis: perpendicular to wind → bends trunk toward wind
            float3 axisPrimary   = normalize(cross(float3(0,1,0), windDir2D));
            // Secondary axis: parallel to wind → lateral sway (polar lean)
            float3 axisSecondary = windDir2D;

            float heightNorm  = saturate(posRest.y / _TrunkHeight);
            float heightCurve = heightNorm * heightNorm;
            float weight      = max(moveR, flutterG);

            float windPhase = t * _TrunkSpeed * _WindSpeed;

            // Shared amplitude modifiers — also use posRest so they're stable
            float turb = Turbulence(posRest + objWorldPos * 0.1, t) * _TurbulenceStrength;
            float amp  = 1.0 + turb;

            // ── 1. Trunk primary lean ──────────────────────────────────────
            float trunkSin = sin(windPhase - _BranchLeadTime * _TrunkSpeed * _WindSpeed);

            #if defined(_LEAN_WIND)
                float trunkWave = _WindLean + trunkSin * (1.0 - _WindLean);
            #else
                float trunkWave = trunkSin;
            #endif

            float trunkAngle = trunkWave * _TrunkStrength * heightCurve * weight * amp;
            posOS = RotateAroundAxis(posOS, axisPrimary, trunkAngle);

            // ── 2. Trunk secondary lateral sway (polar lean) ───────────────
            #if defined(_POLAR_LEAN)
                float lateralWave  = sin(windPhase * _TrunkSecondarySpeed * 0.7 + 1.2)
                                   * _TrunkSecondaryStrength;
                float lateralAngle = lateralWave * _TrunkStrength * 0.35
                                   * heightCurve * weight * amp;
                posOS = RotateAroundAxis(posOS, axisSecondary, lateralAngle);
            #endif

            // ── 3. Branches ────────────────────────────────────────────────
            if (isBranch > 0.2)
            {
                // Use rest-pose XZ distance — stable, never flickers
                float lateralDist = length(posRest.xz);

                // Per-branch unique phase from REST position hash — constant per vertex
                float branchHash  = PosHash(posRest * 0.5 + objWorldPos);
                float phaseOffset = branchHash * _BranchPhaseVariance;

                // Forward sway
                float branchWave  = sin(windPhase * _BranchSpeed + phaseOffset);
                float branchAngle = branchWave * _BranchStrength * moveR * lateralDist * amp;
                posOS = RotateAroundAxis(posOS, axisPrimary, branchAngle);

                // Lateral sway (smaller, different frequency)
                float branchLatWave  = sin(windPhase * _BranchSpeed * 1.31 + phaseOffset + 0.9);
                float branchLatAngle = branchLatWave * _BranchStrength * 0.3 * moveR * amp;
                posOS = RotateAroundAxis(posOS, axisSecondary, branchLatAngle);
            }

            // ── 4. Leaf flutter ────────────────────────────────────────────
            float3 sideDir = normalize(float3(-windDir2D.z, 0.0, windDir2D.x));
            // Use rest-pose angle — stable
            float  phase   = atan2(posRest.x, posRest.z);

            // Per-leaf randomness from REST position — constant per vertex
            float leafHash = PosHash(posRest + objWorldPos * 0.07);
            float phaseVar = leafHash * TWO_PI * _FlutterVariance;
            float speedVar = 0.7 + leafHash * 0.6;           // 0.7 .. 1.3

            // Horizontal flutter
            float hFlutter = sin(t * _FlutterSpeed * speedVar + phase * 3.0 + phaseVar);
            posOS += sideDir * hFlutter * _FlutterStrength * flutterG;

            // Vertical flutter
            float vFlutter = sin(t * _FlutterSpeed * speedVar * 0.9 + phase * 2.0 + phaseVar + 1.5);
            posOS.y += vFlutter * _FlutterStrength * _FlutterVertical * flutterG;

            return posOS;
        }
        ENDHLSL

        // ─────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature _LEAN_WIND
            #pragma shader_feature _POLAR_LEAN
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

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
                float4 shadowCoord : TEXCOORD3;
                float  fogFactor   : TEXCOORD4;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 objWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 posOS = WindDisplace(IN.positionOS.xyz, IN.color, objWorldPos);

                VertexPositionInputs posInputs  = GetVertexPositionInputs(posOS);
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
                clip(texColor.a - _Cutoff);

                InputData lightInput = (InputData)0;
                lightInput.positionWS      = IN.positionWS;
                lightInput.normalWS        = normalize(IN.normalWS);
                lightInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                lightInput.shadowCoord     = IN.shadowCoord;
                lightInput.fogCoord        = IN.fogFactor;

                SurfaceData surfData = (SurfaceData)0;
                surfData.albedo     = texColor.rgb;
                surfData.alpha      = texColor.a;
                surfData.smoothness = 0.0;
                surfData.occlusion  = 1.0;

                float4 color = UniversalFragmentPBR(lightInput, surfData);
                color.rgb = max(color.rgb, texColor.rgb * 0.3);
                color.rgb = MixFog(color.rgb, IN.fogFactor);
                return color;
            }
            ENDHLSL
        }

        // ─────────────────────────────────────────────────────────────────────
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off

            HLSLPROGRAM
            #pragma vertex   shadowVert
            #pragma fragment shadowFrag
            #pragma shader_feature _LEAN_WIND
            #pragma shader_feature _POLAR_LEAN

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

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

            VaryShadow shadowVert(AttrShadow IN)
            {
                VaryShadow OUT;

                float3 objWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 posOS = WindDisplace(IN.positionOS.xyz, IN.color, objWorldPos);

                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float3 posWS    = TransformObjectToWorld(posOS);

                OUT.positionHCS = TransformWorldToHClip(
                    ApplyShadowBias(posWS, normalWS, _MainLightPosition.xyz));
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
