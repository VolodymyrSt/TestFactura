Shader "Custom/TreeTrunkBend_Smooth"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Color", Color) = (1,1,1,1)
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _RoughnessMap ("Roughness/Metal/AO", 2D) = "white" {}

        [Header(Wind)]
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1.0
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0.0
        _WindSpeed ("Speed", Float) = 1.0
        _BendStrength ("Bend Strength", Float) = 0.3
        _WindWaveSize ("Wave Size", Float) = 1.0
        _TrunkHeight ("Trunk Height", Float) = 6.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);  SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RoughnessMap); SAMPLER(sampler_RoughnessMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;

                float _WindDirX, _WindDirZ;
                float _WindSpeed;
                float _BendStrength;
                float _WindWaveSize;
                float _TrunkHeight;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 tangentWS   : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
            };

            float3 ApplyTrunkBend(float3 posOS)
            {
                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS, 1.0)).xyz;
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;

                // 0 = низ, 1 = верх (SMOOTH)
                float height01 = saturate((worldPos.y - pivotWS.y) / max(_TrunkHeight, 0.001));
                float smoothHeight = smoothstep(0.0, 1.0, height01);
                smoothHeight *= smoothHeight; // ще м’якший falloff

                float3 windDir = normalize(float3(_WindDirX, 0.0, _WindDirZ) + 0.0001);
                float time = _Time.y * _WindSpeed;

                // більш “живий” але smooth рух
                float wave =
                    sin(time * _WindWaveSize + worldPos.x * 0.6 + worldPos.z * 0.6) * 0.6 +
                    sin(time * (_WindWaveSize * 0.5) + worldPos.z * 1.2) * 0.4;

                float bend = wave * _BendStrength * smoothHeight;

                posOS.x += windDir.x * bend;
                posOS.z += windDir.z * bend;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;

                float3 posOS = ApplyTrunkBend(v.positionOS.xyz);

                o.positionHCS = TransformObjectToHClip(float4(posOS, 1.0));
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);

                o.normalWS    = TransformObjectToWorldNormal(v.normalOS);
                o.tangentWS   = TransformObjectToWorldDir(v.tangentOS.xyz);
                o.bitangentWS = cross(o.normalWS, o.tangentWS) * v.tangentOS.w;

                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;

                half4 normalSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
                half3 normalTS = UnpackNormal(normalSample);

                float3x3 TBN = float3x3(i.tangentWS, i.bitangentWS, i.normalWS);
                half3 normalWS = normalize(mul(normalTS, TBN));

                half4 rmo = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, i.uv);
                half ao = rmo.b;

                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(normalWS, mainLight.direction));

                half3 col = albedo.rgb * mainLight.color * (NdotL * 0.85 + 0.15) * ao;

                return half4(col, 1.0);
            }

            ENDHLSL
        }
    }
}