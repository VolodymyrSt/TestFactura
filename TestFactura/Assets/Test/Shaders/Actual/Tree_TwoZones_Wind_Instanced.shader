Shader "Custom/Tree_TwoZones_Wind_Instanced"
{
    Properties
    {
        _BaseMap ("Albedo", 2D) = "white" {}
        _BaseColor ("Global Color", Color) = (1,1,1,1)

        [Header(Wind Settings)]
        [Toggle(_USE_WIND_ON)] _UseWind("Enable Wind", Float) = 1.0
        _WindDirX ("Wind Dir X", Range(-1,1)) = 1
        _WindDirZ ("Wind Dir Z", Range(-1,1)) = 0
        _WindSpeed ("Speed", Float) = 1
        _TreeHeight ("Tree Height Mask", Float) = 5.0

        [Header(Zone Control)]
        _ZoneBoundaryZ ("Zone Boundary (Z axis)", Float) = 200.0
        _Zone1Strength ("Zone 1 Strength", Range(0, 2)) = 1.0
        _Zone2Strength ("Zone 2 Strength", Range(0, 2)) = 0.5
        
        _TrunkBend ("Trunk Bend", Float) = 0.5
        _BranchFlutter ("Branch Flutter", Float) = 0.2

        [HideInInspector] _MainLightPosition ("", Vector) = (0,0,0,0)
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
            
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
                UNITY_DEFINE_INSTANCED_PROP(half4, _BaseColor)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirX)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindDirZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindSpeed)
                UNITY_DEFINE_INSTANCED_PROP(float, _TrunkBend)
                UNITY_DEFINE_INSTANCED_PROP(float, _BranchFlutter)
                UNITY_DEFINE_INSTANCED_PROP(float, _TreeHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _ZoneBoundaryZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _Zone1Strength)
                UNITY_DEFINE_INSTANCED_PROP(float, _Zone2Strength)
                UNITY_DEFINE_INSTANCED_PROP(float, _WindPhase)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 vColor : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 ApplyWind(float3 posOS, float4 vColor)
            {
                #if !defined(_USE_WIND_ON)
                    return posOS;
                #endif

                float3 worldPos = mul(GetObjectToWorldMatrix(), float4(posOS,1)).xyz;
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                
                float boundaryZ = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _ZoneBoundaryZ);
                float z1Str = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Zone1Strength);
                float z2Str = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Zone2Strength);

                float localZoneStrength = (pivotWS.z < boundaryZ) ? z1Str : z2Str;

                float treeH = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TreeHeight);
                float height01 = saturate((worldPos.y - pivotWS.y) / treeH);
                float heightEffect = height01 * height01;

                float wX = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirX);
                float wZ = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindDirZ);
                float3 windDir = normalize(float3(wX, 0, wZ) + 0.001);
                
                float wSpeed = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindSpeed);
                float phase = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _WindPhase);
                float time = (_Time.y * wSpeed) + phase;

                float tBend = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _TrunkBend);
                float smoothHeight = pow(height01, 1.5);
                
                //1
                ////float softVColor = smoothstep(0, 1, vColor.r);
                float trunkWave = sin(time + pivotWS.x * 0.5) * tBend * vColor.r * smoothHeight;

                //2
                //float trunkWave = sin(time + pivotWS.x * 0.5) * tBend * smoothHeight;
                
                float noise = frac(dot(worldPos.xyz, float3(12.9898, 78.233, 45.164)));
                float bFlutter = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BranchFlutter);
                float branchWave = sin(time * 2.5 + dot(worldPos.xyz, float3(1.0, 0.5, 1.0)) + noise) * bFlutter * (vColor.g + vColor.b);
                
                float totalWind = (trunkWave + branchWave * (vColor.g + vColor.b)) * localZoneStrength;
                
                posOS.xz += windDir.xz * totalWind;
                return posOS;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                float3 animatedPos = ApplyWind(v.positionOS.xyz, v.color);
                o.positionHCS = TransformObjectToHClip(float4(animatedPos, 1));
                
                float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseST.xy + baseST.zw;
                
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.vColor = v.color; 
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                half4 baseCol = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * baseCol * i.vColor;
                
                Light mainLight = GetMainLight();
                half NdotL = saturate(dot(normalize(i.normalWS), mainLight.direction));
                half3 lighting = mainLight.color * (NdotL * 0.8 + 0.2);
                
                return half4(tex.rgb * lighting, tex.a);
            }
            ENDHLSL
        }
    }
}