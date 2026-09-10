Shader "Custom/TreeWind3Channel"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Wind)]
        _WindDirection ("Wind Direction", Vector) = (1,0,0,0)
        _WindSpeed ("Wind Speed", Float) = 1.0
        _BranchLeadTime ("Branch Lead Time (sec)", Float) = 0.5

        [Header(Lean)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind ("Lean into Wind", Float) = 1.0
        _WindLean ("Wind Lean Weight", Range(0,1)) = 0.3

        [Header(Trunk)]
        _TrunkStrength ("Trunk Strength", Float) = 0.3
        _TrunkSpeed ("Trunk Speed", Float) = 0.5
        _TrunkHeight ("Trunk Height", Float) = 5.0

        [Header(Branches)]
        _BranchStrength ("Branch Strength", Float) = 0.4
        _BranchSpeed ("Branch Speed", Float) = 0.5

        [Header(Flutter)]
        _FlutterStrength ("Flutter Strength", Float) = 0.02
        _FlutterSpeed ("Flutter Speed", Float) = 8.0
    }

    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "RenderPipeline" = "UniversalPipeline" "Queue" = "AlphaTest" }
        Cull Off

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _LEAN_WIND
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST, _BaseColor, _WindDirection;
                float _Cutoff, _WindSpeed, _BranchLeadTime;
                float _WindLean;
                float _TrunkStrength, _TrunkSpeed, _TrunkHeight;
                float _BranchStrength, _BranchSpeed;
                float _FlutterStrength, _FlutterSpeed;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR; // R: вага вигину, G: флаттер, B: 1=гілка/крона
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

            float3 RotateAroundAxis(float3 p, float3 axis, float angle)
            {
                float s = sin(angle), c = cos(angle);
                return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float t = _Time.y;
                float3 windDir = normalize(_WindDirection.xyz);
                float3 posOS = IN.positionOS.xyz;
                float moveR = IN.color.r, flutterG = IN.color.g, isBranch = IN.color.b;

                float3 bendAxis = normalize(cross(float3(0,1,0), windDir));
                float heightNorm = saturate(posOS.y / _TrunkHeight);
                float heightCurve = heightNorm * heightNorm;
                float weight = max(moveR, flutterG);

                float windPhase = t * _TrunkSpeed * _WindSpeed;
                float windWave = sin(windPhase);

                // ---------- 1. СТОВБУР ----------
                float trunkSin = sin(windPhase - _BranchLeadTime * _TrunkSpeed * _WindSpeed);

                #if defined(_LEAN_WIND)
                    float trunkWave = (_WindLean + trunkSin * (1.0 - _WindLean));
                #else
                    float trunkWave = trunkSin;
                #endif

                float trunkAngle = trunkWave * _TrunkStrength * heightCurve * weight;
                posOS = RotateAroundAxis(posOS, bendAxis, trunkAngle);

                // ---------- 2. ГІЛКИ ----------
                if (isBranch > 0.2)
                {
                    float lateralDist = length(IN.positionOS.xyz.xz);
                    float branchAngle = windWave * _BranchStrength * moveR * lateralDist;
                    posOS = RotateAroundAxis(posOS, bendAxis, branchAngle);
                }

                // ---------- 3. ФЛАТТЕР ЛИСТЯ ----------
                float3 sideDir = normalize(float3(-windDir.z, 0, windDir.x));
                float phase = atan2(posOS.x, posOS.z);
                float flutterWave = sin(t * _FlutterSpeed + phase * 3.0);
                posOS += sideDir * flutterWave * _FlutterStrength * flutterG;

                VertexPositionInputs posInputs = GetVertexPositionInputs(posOS);
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS);
                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS = normInputs.normalWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.shadowCoord = GetShadowCoord(posInputs);
                OUT.fogFactor = ComputeFogFactor(posInputs.positionCS.z);
                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                float4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(texColor.a - _Cutoff);
                InputData lightInput = (InputData)0;
                lightInput.positionWS = IN.positionWS;
                lightInput.normalWS = normalize(IN.normalWS);
                lightInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                lightInput.shadowCoord = IN.shadowCoord;
                lightInput.fogCoord = IN.fogFactor;
                SurfaceData surfData = (SurfaceData)0;
                surfData.albedo = texColor.rgb;
                surfData.alpha = texColor.a;
                surfData.smoothness = 0.0;
                surfData.occlusion = 1.0;
                float4 color = UniversalFragmentPBR(lightInput, surfData);
                color.rgb = max(color.rgb, texColor.rgb * 0.3);
                color.rgb = MixFog(color.rgb, IN.fogFactor);
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            HLSLPROGRAM
            #pragma vertex shadowVert
            #pragma fragment shadowFrag
            #pragma shader_feature _LEAN_WIND
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST, _BaseColor, _WindDirection;
                float _Cutoff, _WindSpeed, _BranchLeadTime;
                float _WindLean;
                float _TrunkStrength, _TrunkSpeed, _TrunkHeight;
                float _BranchStrength, _BranchSpeed;
                float _FlutterStrength, _FlutterSpeed;
            CBUFFER_END

            struct AttrShadow { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; float4 color : COLOR; };
            struct VaryShadow { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; };

            float3 RotateAroundAxis(float3 p, float3 axis, float angle)
            {
                float s = sin(angle), c = cos(angle);
                return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
            }

            VaryShadow shadowVert(AttrShadow IN)
            {
                VaryShadow OUT;
                float t = _Time.y;
                float3 windDir = normalize(_WindDirection.xyz);
                float3 posOS = IN.positionOS.xyz;
                float moveR = IN.color.r, flutterG = IN.color.g, isBranch = IN.color.b;
                float3 bendAxis = normalize(cross(float3(0,1,0), windDir));
                float heightNorm = saturate(posOS.y / _TrunkHeight);
                float heightCurve = heightNorm * heightNorm;
                float weight = max(moveR, flutterG);

                float windPhase = t * _TrunkSpeed * _WindSpeed;
                float windWave = sin(windPhase);

                // Стовбур із Lean
                float trunkSin = sin(windPhase - _BranchLeadTime * _TrunkSpeed * _WindSpeed);

                #if defined(_LEAN_WIND)
                    float trunkWave = (_WindLean + trunkSin * (1.0 - _WindLean));
                #else
                    float trunkWave = trunkSin;
                #endif

                float trunkAngle = trunkWave * _TrunkStrength * heightCurve * weight;
                posOS = RotateAroundAxis(posOS, bendAxis, trunkAngle);

                // Гілки
                if (isBranch > 0.2)
                {
                    float lateralDist = length(IN.positionOS.xyz.xz);
                    float branchAngle = windWave * _BranchStrength * moveR * lateralDist;
                    posOS = RotateAroundAxis(posOS, bendAxis, branchAngle);
                }

                // Флаттер
                float3 sideDir = normalize(float3(-windDir.z, 0, windDir.x));
                float phase = atan2(posOS.x, posOS.z);
                float flutterWave = sin(t * _FlutterSpeed + phase * 3.0);
                posOS += sideDir * flutterWave * _FlutterStrength * flutterG;

                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float3 posWS = TransformObjectToWorld(posOS);
                OUT.positionHCS = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, _MainLightPosition.xyz));
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
