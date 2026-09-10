Shader "Custom/URP/SnowByVertexColor"
{
    Properties
    {
        _BaseMap ("Base Texture", 2D) = "white" {}
        _SnowColor ("Snow Color", Color) = (1,1,1,1)
        _SnowAmount ("Snow Strength", Range(0,1)) = 1
        _SnowPower ("Snow Contrast", Range(0.1,5)) = 2
    }

    SubShader
    {
        Tags { 
            "RenderType"="Opaque"
            "Queue"="Geometry"
            "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR; // Vertex Color
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float snowMask : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            float4 _SnowColor;
            float _SnowAmount;
            float _SnowPower;

            Varyings vert (Attributes v)
            {
                Varyings o;

                o.positionHCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;

                float mask = v.color.r;

                // Контраст маски
                mask = pow(mask, _SnowPower);

                o.snowMask = mask;

                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                float snow = saturate(i.snowMask * _SnowAmount);

                half4 finalCol = lerp(baseCol, _SnowColor, snow);

                return finalCol;
            }

            ENDHLSL
        }
    }
}