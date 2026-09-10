Shader "Custom/SimpleWind_Final_Fix"
{
    Properties
    {
        _BaseMap       ("Albedo", 2D)  = "white" {}
        _BaseColor     ("Color", Color) = (1,1,1,1)
        
        [Header(Wind Toggle)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0

        [Header(Wind Direction)]
        _WindDirX      ("Wind Dir X", Range(-1,1)) = 1.0
        _WindDirZ      ("Wind Dir Z", Range(-1,1)) = 0.0
        
        [Header(General Settings)]
        _WindStrength  ("Strength", Float) = 1.0
        _WindSpeed     ("Speed", Float) = 1.0
        
        [Header(Bending Controls)]
        _TrunkBend     ("Trunk Bend (Red Mask)", Float) = 1.5
        _BranchFlutter ("Branch Flutter (Blue Mask)", Float) = 0.5
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

            // Ця директива створює два варіанти шейдера: з вітром і без
            #pragma shader_feature _USE_WIND_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                float  _WindDirX, _WindDirZ;
                float  _WindStrength, _WindSpeed;
                float  _TrunkBend, _BranchFlutter;
            CBUFFER_END

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
                half3  normalWS    : TEXCOORD1;
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                // ПЕРЕВІРКА: якщо галочка вимкнена, просто повертаємо оригінальну позицію
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float redMask = saturate(vColor.r);
                float blueMask = saturate(vColor.b);

                if (redMask < 0.001) return posOS;

                float3 objectPivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 windDir = normalize(float3(_WindDirX, 0, _WindDirZ) + float3(0.0001, 0, 0));
                float time = _Time.y * _WindSpeed;

                float trunkSway = sin(time + objectPivotWS.x + objectPivotWS.z) * _TrunkBend;
                float finalTrunk = trunkSway * redMask;
                
                float branchNoise = sin(time * 3.0 + posOS.x + posOS.y) * _BranchFlutter;
                float finalBranch = branchNoise * blueMask;
                
                float totalOffset = (finalTrunk + finalBranch) * _WindStrength;
                totalOffset = clamp(totalOffset, -2.5, 2.5);

                posOS.x += windDir.x * totalOffset;
                posOS.z += windDir.z * totalOffset;
                posOS.y -= abs(totalOffset) * 0.2 * redMask;

                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 posOS = ApplyWind(v.positionOS.xyz, v.color);
                o.positionHCS = TransformObjectToHClip(float4(posOS, 1.0));
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(normalize(i.normalWS), mainLight.direction));
                half3 col = albedo.rgb * mainLight.color * (NdotL * 0.8 + 0.2);
                return half4(col, albedo.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _USE_WIND_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _WindDirX, _WindDirZ, _WindStrength, _WindSpeed, _TrunkBend, _BranchFlutter;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float4 color : COLOR; };
            struct Varyings { float4 positionHCS : SV_POSITION; };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float redMask = saturate(vColor.r);
                float blueMask = saturate(vColor.b);

                // smooth mask замість if (щоб не ламати GPU divergence)
                redMask = smoothstep(0.05, 1.0, redMask);

                float3 objectPivotWS = GetObjectToWorldMatrix()._m03_m13_m23;

                float3 posWS = mul(GetObjectToWorldMatrix(), float4(posOS, 1.0)).xyz;

                // smooth height gradient (важливо для "smooth bend")
                float treeBottom = objectPivotWS.y - 2.0;
                float treeHeight = 8.0;

                float height01 = saturate((posWS.y - treeBottom) / treeHeight);
                float heightGradient = smoothstep(0.0, 1.0, height01);
                heightGradient *= heightGradient;

                float3 windDir = normalize(float3(_WindDirX, 0, _WindDirZ) + 0.0001);
                float time = _Time.y * _WindSpeed;

                // trunk sway (smooth + stable)
                float trunkSway =
                    sin(time + objectPivotWS.x + objectPivotWS.z) * _TrunkBend;

                float trunk = trunkSway * redMask * heightGradient;

                // branch flutter (less chaotic, more natural)
                float branchNoise =
                    sin(time * 2.5 + posWS.x * 0.4 + posWS.z * 0.4) * _BranchFlutter;

                float branch = branchNoise * blueMask;

                float totalOffset = (trunk + branch) * _WindStrength;

                // soft clamp (краще ніж жорсткий clamp)
                totalOffset = totalOffset / (1.0 + abs(totalOffset));

                posOS.x += windDir.x * totalOffset;
                posOS.z += windDir.z * totalOffset;

                return posOS;
            }
            
            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionHCS = TransformObjectToHClip(float4(ApplyWind(v.positionOS.xyz, v.color), 1.0));
                return o;
            }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}