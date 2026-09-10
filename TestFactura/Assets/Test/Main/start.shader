Shader "Custom/Tree_Wind_Stable"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        _WindSpeed ("Wind Speed", Float) = 1.5
        _WindStrength ("Wind Strength", Float) = 0.3
        
        _BranchSpeed ("Branch Speed", Float) = 4.0
        _BranchSway ("Branch Sway Strength", Float) = 0.15
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSway)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 color      : COLOR;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float fogFactor    : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                float time = _Time.y;
                
                float trunkSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float trunkStrength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
                float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchSway = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSway);

                float trunkWind = sin(time * trunkSpeed) * trunkStrength;
                float trunkWeight = vColor.r;
                posOS.xz += trunkWind * trunkWeight;

                float branchWind = sin(time * branchSpeed + (posOS.y + posOS.x) * 2.0) * branchSway;
                float branchWeight = vColor.b;
                posOS.x += branchWind * branchWeight;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);

                o.positionCS = TransformObjectToHClip(animatedPos);
                
                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;
                
                o.fogFactor = ComputeFogFactor(o.positionCS.z);

                return o;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);

                clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));

                col.rgb = MixFog(col.rgb, IN.fogFactor);

                return col;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4,  _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float,  _Cutoff)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _WindStrength)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float,  _BranchSway)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 color      : COLOR;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                float time = _Time.y;
                
                float trunkSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float trunkStrength = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindStrength);
                float branchSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSpeed);
                float branchSway = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchSway);

                float trunkWind = sin(time * trunkSpeed) * trunkStrength;
                float trunkWeight = vColor.r;
                posOS.xz += trunkWind * trunkWeight;

                float branchWind = sin(time * branchSpeed + (posOS.y + posOS.x) * 2.0) * branchSway;
                float branchWeight = vColor.b;
                posOS.x += branchWind * branchWeight;

                return posOS;
            }

            Varyings vertShadow(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);

                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                float4 posWS = float4(TransformObjectToWorld(float4(animatedPos, 1)).xyz, 1);
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(posWS.xyz, normalWS, 0));

                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;

                return o;
            }

            half4 fragShadow(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 col = texColor * UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                clip(col.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
                
                return 0;
            }
            ENDHLSL
        }
    }
    Fallback "Universal Render Pipeline/Lit"
}