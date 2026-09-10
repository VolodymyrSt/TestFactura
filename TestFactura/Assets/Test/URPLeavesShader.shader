Shader "Custom/URPLeavesShader"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap ("Albedo (RGB)", 2D) = "white" {}
        _NoiseMap ("Noise Texture", 2D) = "white" {}
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1.0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5

        [Header(Wind and Bending)]
        _BendFactor ("Bend Factor", Range(0, 5)) = 1.0
        _Speed ("Wind Speed", Range(0, 50)) = 10.0
        _Direction ("Wind Direction", Vector) = (1.0, 1.0, 0.0, 0.0)
        _NoiseScale ("Noise Scale", Range(0, 2)) = 0.5
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "TransparentCutout" 
            "Queue" = "AlphaTest" 
            "RenderPipeline" = "UniversalPipeline" 
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }

        LOD 300
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _NoiseMap_ST;
            half4 _BaseColor;
            half _Cutoff;
            half _Smoothness;
            half _Metallic;
            half _BumpScale;
            float _BendFactor;
            float _Speed;
            float4 _Direction;
            float _NoiseScale;
        CBUFFER_END

        TEXTURE2D(_BaseMap);        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_BumpMap);        SAMPLER(sampler_BumpMap);
        TEXTURE2D(_NoiseMap);       SAMPLER(sampler_NoiseMap);

        float3 ApplyWindDisplacement(float3 positionOS, float2 uv)
        {
            // Base swaying motion
            float remapedPosY = positionOS.y * (_BendFactor / 100.0) * sin(_Time.y * _Speed);
            float distortedPosY = (remapedPosY * remapedPosY) - remapedPosY;
            float2 directedPos = distortedPosY * _Direction.xy;
            float3 distortedPos = float3(directedPos.x, 0.0, directedPos.y) + positionOS;

            // Noise sampling via Level-of-Detail (Mip 0)
            float2 noiseUV = positionOS.xz * _NoiseScale + (_Time.y * _Speed * 0.05);
            float noiseX = (0.5 - SAMPLE_TEXTURE2D_LOD(_NoiseMap, sampler_NoiseMap, noiseUV, 0).r) * (_BendFactor / 5.0);
            float noiseY = (0.5 - SAMPLE_TEXTURE2D_LOD(_NoiseMap, sampler_NoiseMap, noiseUV + float2(0.37, 0.52), 0).r) * (_BendFactor / 5.0);
            float noiseZ = (0.5 - SAMPLE_TEXTURE2D_LOD(_NoiseMap, sampler_NoiseMap, noiseUV + float2(0.83, 0.19), 0).r) * (_BendFactor / 5.0);
            float3 noise = float3(noiseX, noiseY, noiseZ);

            float weight = saturate(uv.x + uv.y);
            return lerp(positionOS, distortedPos + noise, weight);
        }
        ENDHLSL

        // ------------------------------------------------------------------
        // Forward Lit Pass
        // ------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0

            // URP Keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS               : SV_POSITION;
                float3 positionWS               : TEXCOORD0;
                float3 normalWS                 : TEXCOORD1;
                float4 tangentWS                : TEXCOORD2;
                float2 uv                       : TEXCOORD3;
            };

            Varyings LitPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                float3 displacedOS = ApplyWindDisplacement(input.positionOS.xyz, input.uv);
                VertexPositionInputs positionInputs = GetVertexPositionInputs(displacedOS);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);

                output.normalWS = normalInputs.normalWS;
                output.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w * GetOddNegativeScale());

                return output;
            }

            half4 LitPassFragment(Varyings input, half facing : VFACE) : SV_Target
            {
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                clip(albedoAlpha.a - _Cutoff);

                // Two-sided normal flipping
                float3 normalWS = normalize(input.normalWS);
                normalWS = facing > 0 ? normalWS : -normalWS;

                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = cross(normalWS, tangentWS) * input.tangentWS.w;
                half4 normalSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv);
                float3 normalTS = UnpackNormalScale(normalSample, _BumpScale);
                normalWS = TransformTangentToWorld(normalTS, half3x3(tangentWS, bitangentWS, normalWS));

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalize(normalWS);
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedoAlpha.rgb;
                surfaceData.metallic = _Metallic;
                surfaceData.smoothness = _Smoothness;
                surfaceData.normalTS = normalTS;
                surfaceData.alpha = albedoAlpha.a;

                return UniversalFragmentPBR(inputData, surfaceData);
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------
        // Shadow Caster Pass (Accurate moving foliage shadows)
        // ------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
            };

            float3 _LightDirection;

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                float3 displacedOS = ApplyWindDisplacement(input.positionOS.xyz, input.uv);
                float3 positionWS = TransformObjectToWorld(displacedOS);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);

                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_Target
            {
                half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------
        // Depth-Only Pass (SSAO & Depth Prepass Support)
        // ------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthPassVertex
            #pragma fragment DepthPassFragment

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
            };

            Varyings DepthPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                float3 displacedOS = ApplyWindDisplacement(input.positionOS.xyz, input.uv);
                output.positionCS = TransformObjectToHClip(displacedOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 DepthPassFragment(Varyings input) : SV_Target
            {
                half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}