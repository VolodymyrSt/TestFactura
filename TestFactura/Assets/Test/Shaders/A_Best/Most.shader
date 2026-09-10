Shader "Custom/LowPolyTreeWind_URP"
{
    Properties
    {
        _BaseMap    ("Albedo", 2D) = "white" {}
        _BaseColor  ("Global Color", Color) = (1,1,1,1)
        _Cutoff     ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Base)]
        [Toggle(_USE_WIND_ON)] _UseWind ("Enable Wind", Float) = 1.0
        _WindSpeed  ("Speed", Float) = 1
        _WindDirX   ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ   ("Wind Dir Z", Range(-1,1)) = 0

        [Header(Lean)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind ("Lean into Wind", Float) = 1.0
        _WindLeanWeight ("Wind Lean Static", Range(0,1)) = 0.5

        [Header(Trunk)]
        _TrunkBend  ("Trunk Bend", Float) = 0.5

        [Header(Branch)]
        _BranchBend     ("Branch Bend",      Float) = 0.3
        _BranchSpeed    ("Branch Speed",     Float) = 1.3
        _BranchFlutter  ("Branch Flutter",   Float) = 0.2
        _ShimmerIntensity ("Shimmer Intensity", Range(0,2)) = 0.4
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #pragma shader_feature_local _USE_WIND_ON
            #pragma shader_feature_local _LEAN_WIND

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                float  _Cutoff;

                float  _UseWind;
                float  _WindSpeed;
                float  _WindDirX;
                float  _WindDirZ;

                float  _LeanIntoWind;
                float  _WindLeanWeight;

                float  _TrunkBend;

                float  _BranchBend;
                float  _BranchSpeed;
                float  _BranchFlutter;
                float  _ShimmerIntensity;
            CBUFFER_END

            // ---------------------------------------------------------------------------
            // Helpers
            // ---------------------------------------------------------------------------

            float2 SafeNorm2(float2 v)
            {
                return v * rsqrt(max(dot(v, v), 1e-4));
            }

            float3 SafeNorm3(float3 v)
            {
                return v * rsqrt(max(dot(v, v), 1e-4));
            }

            // Rodrigues rotation
            float3 RotateAroundAxis(float3 p, float3 axis, float angle)
            {
                float s, c;
                sincos(angle, s, c);
                return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
            }

            // ---------------------------------------------------------------------------
            // Vertex color convention (painted per-mesh):
            //   R – trunk influence  (0 = root, 1 = top of trunk)
            //   G – branch influence (0 = none, 1 = branch tip)
            //   B – leaf / fine flutter influence
            // ---------------------------------------------------------------------------

            // ---------------------------------------------------------------------------
            // Trunk bend  (object space, rotates whole trunk)
            // ---------------------------------------------------------------------------
            void ApplyTrunkBendOS(inout float3 posOS, inout float3 normOS,
                                  float trunkMask, float2 windDir2, float time)
            {
                // Steady lean component
                float leanAngle = 0.0;
            #if defined(_LEAN_WIND)
                leanAngle = radians(_TrunkBend * _WindLeanWeight * 12.0);
            #endif

                // Slow swaying gust
                float gustFreq = 0.55 * _WindSpeed;
                float gust = 0.5 + 0.5 * sin(time * gustFreq);
                float swayAngle = radians(_TrunkBend * lerp(1.5, 8.0, gust));

                float totalAngle = (leanAngle + swayAngle) * trunkMask;
                totalAngle = clamp(totalAngle, 0.0, radians(30.0));

                float3 windDirWS  = float3(windDir2.x, 0.0, windDir2.y);
                float3 windDirOS  = SafeNorm3(mul((float3x3)unity_WorldToObject, windDirWS));
                windDirOS.y = 0.0;
                windDirOS = SafeNorm3(windDirOS);

                float3 upOS   = float3(0.0, 1.0, 0.0);
                float3 bendAxis = SafeNorm3(cross(upOS, windDirOS));

                posOS  = RotateAroundAxis(posOS,  bendAxis, totalAngle);
                normOS = RotateAroundAxis(normOS, bendAxis, totalAngle);

                // Subtle side-sway (perpendicular to wind)
                float3 sideAxis = SafeNorm3(cross(upOS, float3(-windDirOS.z, 0.0, windDirOS.x)));
                float sideWave  = sin(time * _WindSpeed * 0.7 + 1.57);
                float sideAngle = radians(_TrunkBend * 0.8) * sideWave * trunkMask;
                sideAngle = clamp(sideAngle, radians(-4.0), radians(4.0));

                posOS  = RotateAroundAxis(posOS,  sideAxis, sideAngle);
                normOS = RotateAroundAxis(normOS, sideAxis, sideAngle);
            }

            // ---------------------------------------------------------------------------
            // Branch bend + flutter  (world space, after trunk transform)
            // ---------------------------------------------------------------------------
            float3 ApplyBranchWindWS(float3 posWS, float branchMask, float leafMask,
                                     float2 windDir2, float time)
            {
                float2 windSide2 = float2(-windDir2.y, windDir2.x);

                // ---- Branch primary swing ----
                float branchFreq = _BranchSpeed * _WindSpeed;
                float branchWave = sin(time * branchFreq + dot(posWS.xz, windDir2) * 2.5);
                float branchAmp  = _BranchBend * 0.04;

                posWS.xz += windDir2  * branchWave * branchAmp * branchMask;
                posWS.y  += branchWave * branchAmp * 0.3 * branchMask;

                // ---- Branch flutter (higher frequency side oscillation) ----
                float flutterFreq = branchFreq * 2.3;
                float flutterWave = sin(time * flutterFreq + dot(posWS.xz, windSide2) * 4.0
                                        + posWS.y * 1.2);
                float flutterAmp  = _BranchFlutter * 0.025;

                posWS.xz += windSide2 * flutterWave * flutterAmp * branchMask;

                // ---- Leaf shimmer  (fast fine-detail flutter on B channel) ----
                float shimFreq  = branchFreq * 5.5;
                float shimWaveA = sin(time * shimFreq
                                      + dot(posWS.xz, float2(0.73, 1.21)) * 9.0
                                      + posWS.y * 2.5);
                float shimWaveB = sin(time * (shimFreq * 1.37)
                                      + dot(posWS.xz, float2(-0.55, 1.91)) * 13.0);
                float shimmer   = (shimWaveA + shimWaveB * 0.5) / 1.5;

                float shimAmp   = _ShimmerIntensity * 0.012;
                posWS.xz += windDir2  * shimmer * shimAmp * 0.65 * leafMask;
                posWS.xz += windSide2 * shimmer * shimAmp * 0.35 * leafMask;

                // ---- Vertical shimmer ----
                float vertWave = sin(time * (shimFreq * 0.7)
                                     + posWS.y * 5.0
                                     + dot(posWS.xz, windDir2));
                posWS.y += vertWave * shimAmp * 0.5 * leafMask;

                return posWS;
            }

            // ---------------------------------------------------------------------------
            // Structs
            // ---------------------------------------------------------------------------

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;  // R=trunk, G=branch, B=leaf
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : TEXCOORD0;
                float2 uv          : TEXCOORD1;
                half4  vertColor   : TEXCOORD2;
            };

            // ---------------------------------------------------------------------------
            // Vertex
            // ---------------------------------------------------------------------------

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 posOS  = IN.positionOS.xyz;
                float3 normOS = IN.normalOS;

            #if defined(_USE_WIND_ON)
                float time = _Time.y;

                float2 windDir2 = float2(_WindDirX, _WindDirZ);
                if (dot(windDir2, windDir2) < 1e-4)
                    windDir2 = float2(1.0, 0.0);
                windDir2 = SafeNorm2(windDir2);

                float trunkMask  = saturate(IN.color.r);
                float branchMask = saturate(IN.color.g);
                float leafMask   = saturate(IN.color.b);

                // Trunk profile: stiffer at base, bends more toward top
                float trunkProfile = pow(trunkMask, 2.5);

                // -- Trunk bend (OS) --
                ApplyTrunkBendOS(posOS, normOS, trunkProfile, windDir2, time * _WindSpeed);

                // -- Branch & leaf (WS) --
                float3 posWS = TransformObjectToWorld(posOS);
                posWS = ApplyBranchWindWS(posWS, branchMask, leafMask, windDir2, time);

                float3 normalWS = TransformObjectToWorldNormal(normOS);

                OUT.positionHCS = TransformWorldToHClip(posWS);
                OUT.normalWS    = normalize(normalWS);
            #else
                float3 posWS    = TransformObjectToWorld(posOS);
                OUT.positionHCS = TransformWorldToHClip(posWS);
                OUT.normalWS    = normalize(TransformObjectToWorldNormal(normOS));
            #endif

                OUT.uv        = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.vertColor = IN.color;

                return OUT;
            }

            // ---------------------------------------------------------------------------
            // Fragment
            // ---------------------------------------------------------------------------

            half4 frag(Varyings IN) : SV_Target
            {
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                // Alpha clip
                clip(baseTex.a - _Cutoff);

                half3 normalWS = normalize(IN.normalWS);
                Light mainLight = GetMainLight();

                half ndotl = saturate(dot(normalWS, mainLight.direction));
                half3 ambient  = SampleSH(normalWS);
                half3 lighting = ambient + mainLight.color.rgb * ndotl;

                half3 finalColor = baseTex.rgb * lighting;

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }

    FallBack Off
}
