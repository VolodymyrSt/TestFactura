Shader "Custom/Best"
{
    Properties
    {
        _BaseMap  ("Albedo", 2D) = "white" {}
        _BaseColor("Global Color", Color) = (1,1,1,1)

        [Header(Wind)]
        _WindSpeed ("Speed",      Float)       = 1
        _WindDirX  ("Dir X",      Range(-1,1)) = 1
        _WindDirZ  ("Dir Z",      Range(-1,1)) = 0
        _TrunkBend  ("Trunk Bend",  Float)      = 0.5
        _LeanWeight ("Lean Weight", Range(0,1)) = 0.5
        _Flutter    ("Flutter",     Float)      = 0.2
    }

    SubShader
    {
        Tags
        {
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
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float,  _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float,  _LeanWeight)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Flutter)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;      // R=trunk, G=leaf
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                float3 restPosOS = posOS;

                float3 windDir = normalize(float3(UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX),0,
                    UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ) + 0.001
                ));

                float t          = _Time.y * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float tBend      = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float leanWeight = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _LeanWeight);
                float flutter    = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Flutter);

                float trunkMask = vColor.r;
                float leafMask  = vColor.g;

                // ── Trunk sway + lean ───────────────────────────────────
                float sway = saturate(sin(t) * 0.5 + 0.5);

                float angle = sway * tBend * trunkMask;

                float sinA = sin(angle);
                float cosA = cos(angle);

                posOS.xyz += windDir * (posOS.y * sinA) * trunkMask;
                posOS.y   += posOS.y * (cosA - 1.0)     * trunkMask;

                // ── Leaf flutter ────────────────────────────────────────
                float noise    = frac(dot(restPosOS, float3(12.9898, 78.233, 45.164)));
                float wave     = sin(t * 2.5 + noise * 6.0) * flutter;
                float shimmer  = sin(t * 8.0 + noise * 12.0) * flutter * 0.4;

                posOS.xyz += windDir * (wave + shimmer) * leafMask;
                posOS.y   += shimmer * leafMask * 0.3;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 pos    = ApplyWind(v.positionOS.xyz, v.color);
                o.positionHCS = TransformObjectToHClip(float4(pos, 1));
                o.normalWS    = TransformObjectToWorldNormal(v.normalOS);

                float4 st = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * st.xy + st.zw;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                half4 tex  = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                half4 col  = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);

                Light mainLight = GetMainLight();
                float NdotL     = saturate(dot(normalize(i.normalWS), mainLight.direction));
                float3 lighting = mainLight.color * (NdotL + 0.25);

                return half4(tex.rgb * col.rgb * lighting, tex.a);
            }

            ENDHLSL
        }
    }
}