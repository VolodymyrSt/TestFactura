Shader "Custom/Tree_Simple_Wind"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)

        [Header(Wind)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0
        _WindStrength ("Strength", Float) = 1
        _WindSpeed ("Speed", Float) = 1
        _TreeHeight ("Tree Height Mask", Float) = 5.0

        _TrunkBend ("Trunk Bend", Float) = 0.5
        _BranchFlutter ("Branch Flutter", Float) = 0.2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _USE_WIND_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            float _GlobalWindStrength;

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                float _WindDirX, _WindDirZ;
                float _WindStrength, _WindSpeed;
                float _TrunkBend, _BranchFlutter, _TreeHeight;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS,1)).xyz;
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;

                float height01 = saturate((worldPos.y - pivotWS.y) / _TreeHeight);
                float heightEffect = height01 * height01;

                float3 windDir = normalize(float3(_WindDirX, 0, _WindDirZ) + 0.001);
                float time = _Time.y * _WindSpeed;

                float trunkWave = sin(time + pivotWS.x) * _TrunkBend * vColor.r * heightEffect;
                float branchWave = sin(time * 2.0 + worldPos.y) * _BranchFlutter * (vColor.g + vColor.b);

                float totalWind = (trunkWave + branchWave) * _WindStrength * _GlobalWindStrength;
                
                posOS.xz += windDir.xz * totalWind;
                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);
                o.positionHCS = TransformObjectToHClip(float4(animatedPos, 1));
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(normalize(i.normalWS), mainLight.direction));
                half3 lighting = mainLight.color * (NdotL * 0.8 + 0.2);
                return half4(tex.rgb * lighting, tex.a);
            }
            ENDHLSL
        }
    }
}