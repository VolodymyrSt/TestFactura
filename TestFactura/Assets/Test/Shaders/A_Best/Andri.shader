Shader "Custom/LowPolyTreeWind_URP"
{
    Properties
    {
        _BaseMap ("Base Map / Palette Texture", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)

        _WindDirection ("Wind Direction XZ (use X and Z)", Vector) = (1,0,0,0)

        _WindStrength ("Wind Strength", Range(0,8)) = 2.0
        _GustAmount ("Gust Amount", Range(0,2)) = 0.6
        _TrunkFlexibility ("Trunk Flexibility", Range(0.2,3)) = 1.0
        _TrunkRecovery ("Trunk Recovery", Range(0,2)) = 0.8
        _CrownResponse ("Crown Response", Range(0,2)) = 1.0
        _LeafFlutter ("Leaf Flutter", Range(0,3)) = 0.8

        _StructureFollow ("Structure Follow", Range(0,1)) = 1.0
        _TreeBaseY ("Setup: Tree Base Y", Float) = 0
        _TreeHeight ("Setup: Tree Height", Float) = 4

        _AmbientBoost ("Ambient Boost", Range(0,2)) = 0.25
        _DebugWindMask ("Debug Wind RGB", Range(0,1)) = 0
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;

                float4 _WindDirection;

                float _WindStrength;
                float _GustAmount;
                float _TrunkFlexibility;
                float _TrunkRecovery;
                float _CrownResponse;
                float _LeafFlutter;

                float _StructureFollow;
                float _TreeBaseY;
                float _TreeHeight;

                float _AmbientBoost;
                float _DebugWindMask;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                half4 color       : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : TEXCOORD0;
                float2 uv          : TEXCOORD1;
                half4 windMask     : TEXCOORD2;
            };

            float2 SafeNormalize2(float2 v)
            {
                float lenSq = max(dot(v, v), 0.0001);
                return v * rsqrt(lenSq);
            }

            float3 SafeNormalize3(float3 v)
            {
                float lenSq = max(dot(v, v), 0.0001);
                return v * rsqrt(lenSq);
            }

            float3 RotateAroundAxis(float3 p, float3 axis, float angle)
            {
                float s = sin(angle);
                float c = cos(angle);
                return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
            }

            float SmoothSaturateWind(float windStrength)
            {
                return 1.0 - exp(-max(windStrength, 0.0) * 0.34);
            }

            float GetHeightFollowMask(float3 positionOS, float flex01)
            {
                // Нормалізована висота дерева.
                // 0 = низ стовбура
                // 1 = верх дерева
                float height01 = saturate((positionOS.y - _TreeBaseY) / max(_TreeHeight, 0.001));

                // Нижня частина тримається жорсткіше,
                // верх і гілки слідують за основним згином.
                float heightPower = lerp(2.4, 1.45, flex01);

                return pow(height01, heightPower);
            }

            void ApplyTreeBendOS(inout float3 positionOS, inout float3 normalOS, half4 windMask)
            {
                float time = _Time.y;

                float r = saturate(windMask.r);
                float g = saturate(windMask.g);
                float b = saturate(windMask.b);

                float2 windDir2 = float2(_WindDirection.x, _WindDirection.z);

                if (dot(windDir2, windDir2) < 0.0001)
                    windDir2 = float2(1.0, 0.0);

                windDir2 = SafeNormalize2(windDir2);

                float3 windDirWS = float3(windDir2.x, 0.0, windDir2.y);

                float3 windDirOS = mul((float3x3)unity_WorldToObject, windDirWS);
                windDirOS.y = 0.0;
                windDirOS = SafeNormalize3(windDirOS);

                float3 upOS = float3(0.0, 1.0, 0.0);

                float3 bendAxis = SafeNormalize3(cross(upOS, windDirOS));

                float3 sideDirOS = float3(-windDirOS.z, 0.0, windDirOS.x);
                sideDirOS = SafeNormalize3(sideDirOS);
                float3 sideAxis = SafeNormalize3(cross(upOS, sideDirOS));

                float wind01 = saturate(_WindStrength / 8.0);
                float windCurve = SmoothSaturateWind(_WindStrength);

                float flex01 = saturate((_TrunkFlexibility - 0.2) / 2.8);
                float flexScale = lerp(0.55, 1.22, flex01);

                // -----------------------------
                // 1. LOCAL R MASK
                // -----------------------------
                // R тепер означає локальну гнучкість.
                // Але R більше НЕ є єдиним способом слідувати за стовбуром.
                float profilePower = lerp(3.8, 2.05, flex01);
                float rBendMask = pow(r, profilePower);

                // -----------------------------
                // 2. STRUCTURE FOLLOW MASK
                // -----------------------------
                // Це головний новий фікс.
                // Навіть якщо початок гілки R чорний,
                // але він знаходиться високо на дереві,
                // він слідує за основним згином стовбура.
                float heightFollowMask = GetHeightFollowMask(positionOS, flex01) * _StructureFollow;

                // Основна структурна маска:
                // - R працює як раніше
                // - висота дерева додає наслідування згину
                // - G/B дуже слабо допомагають кроні триматися разом
                float paintFollowHint = saturate(r * 0.75 + g * 0.12 + b * 0.06);

                float structureMask = max(rBendMask, heightFollowMask);
                structureMask = max(structureMask, heightFollowMask * paintFollowHint * 0.35);

                // Низ дерева не має рухатися.
                // Це страхує навіть якщо низ випадково трохи пофарбований.
                float rootLock = smoothstep(0.02, 0.12, saturate((positionOS.y - _TreeBaseY) / max(_TreeHeight, 0.001)));
                structureMask *= rootLock;

                if (structureMask <= 0.0001 && r <= 0.0001 && g <= 0.0001 && b <= 0.0001)
                    return;

                // -----------------------------
                // 3. WIND AND GUSTS
                // -----------------------------
                float gustSpeed = 0.75 + _WindStrength * 0.55;

                float gustWave = 0.5 + 0.5 * sin(
                    time * gustSpeed +
                    positionOS.y * 0.18
                );

                float gustInfluence = _GustAmount * lerp(0.10, 0.38, wind01);
                float gust = 1.0 + gustWave * gustInfluence;
                gust = min(gust, 1.45);

                // Реалістичний ліміт згину стовбура.
                float maxAngleDeg = lerp(2.0, 29.0, windCurve) * flexScale;
                maxAngleDeg = min(maxAngleDeg, 33.0);

                float baseAngle = radians(maxAngleDeg) * gust;

                // Пружне повернення.
                float recoverySpeed = 0.9 + _WindStrength * 1.75;

                float recoveryWave = 0.5 + 0.5 * sin(
                    time * recoverySpeed +
                    structureMask * 2.3
                );

                recoveryWave = pow(recoveryWave, 1.4 + _TrunkRecovery * 1.45);

                float recoveryAmount = lerp(0.18, 0.32, wind01) * _TrunkRecovery;

                float recoveryAngle =
                    baseAngle *
                    recoveryAmount *
                    recoveryWave;

                float trunkAngle =
                    max(baseAngle - recoveryAngle, 0.0) *
                    structureMask;

                // Основний згин.
                // Тепер його наслідують і чорні початки гілок,
                // бо вони беруть structureMask по висоті.
                positionOS = RotateAroundAxis(positionOS, bendAxis, trunkAngle);
                normalOS = RotateAroundAxis(normalOS, bendAxis, trunkAngle);

                // -----------------------------
                // 4. CROWN FOLLOW
                // -----------------------------
                // Крона повинна йти разом зі стовбуром і гілками,
                // але не відриватись окремо.
                float crownMask = saturate(structureMask * 0.9 + r * 0.35 + g * 0.08);
                crownMask = pow(crownMask, 0.9);

                float crownAngle =
                    trunkAngle *
                    crownMask *
                    _CrownResponse *
                    lerp(0.12, 0.28, wind01);

                crownAngle = min(crownAngle, radians(7.0));

                positionOS = RotateAroundAxis(positionOS, bendAxis, crownAngle);
                normalOS = RotateAroundAxis(normalOS, bendAxis, crownAngle);

                // Дуже малий дрейф у напрямку вітру.
                // Він дає відчуття тиску вітру, але не розриває крону.
                float crownDrift =
                    crownMask *
                    _CrownResponse *
                    windCurve *
                    gust *
                    lerp(0.0008, 0.0045, wind01);

                positionOS += windDirOS * crownDrift;

                // -----------------------------
                // 5. SIDE SWAY
                // -----------------------------
                // Бокове хитання як у цілого стебла, не хвиля по стовбуру.
                float sideSpeed = 0.65 + _WindStrength * 0.42;
                float sideWave = sin(time * sideSpeed + 1.57);

                float sideAngle =
                    radians(lerp(0.12, 1.45, windCurve)) *
                    _TrunkRecovery *
                    sideWave *
                    structureMask;

                sideAngle = clamp(sideAngle, radians(-1.7), radians(1.7));

                positionOS = RotateAroundAxis(positionOS, sideAxis, sideAngle);
                normalOS = RotateAroundAxis(normalOS, sideAxis, sideAngle);
            }

            float3 ApplyLeafWindWS(float3 positionWS, half4 windMask)
            {
                float time = _Time.y;

                float g = saturate(windMask.g);
                float b = saturate(windMask.b);

                if (g <= 0.0001 && b <= 0.0001)
                    return positionWS;

                float2 windDir2 = float2(_WindDirection.x, _WindDirection.z);

                if (dot(windDir2, windDir2) < 0.0001)
                    windDir2 = float2(1.0, 0.0);

                windDir2 = SafeNormalize2(windDir2);

                float2 windSide2 = float2(-windDir2.y, windDir2.x);

                float wind01 = saturate(_WindStrength / 8.0);
                float windCurve = SmoothSaturateWind(_WindStrength);

                // На сильному вітрі листя рухається швидше,
                // але амплітуда лишається контрольованою.
                float leafSpeedMain = 2.4 + _WindStrength * 2.8;
                float leafSpeedFast = 8.0 + _WindStrength * 6.0;

                float gustSpeed = 0.9 + _WindStrength * 0.9;

                float gustWave = 0.5 + 0.5 * sin(
                    time * gustSpeed +
                    dot(positionWS.xz, windDir2) * 0.35
                );

                float gust = 1.0 + gustWave * _GustAmount * lerp(0.12, 0.42, wind01);
                gust = min(gust, 1.38);

                // Дуже малий постійний зсув листя.
                // Основну форму крони тримає Structure Follow, а не G.
                float leafWindPush =
                    g *
                    _LeafFlutter *
                    windCurve *
                    gust *
                    lerp(0.0008, 0.004, wind01);

                positionWS.xz += windDir2 * leafWindPush;

                // Середнє коливання.
                float leafWaveA = sin(
                    time * leafSpeedMain +
                    dot(positionWS.xz, float2(0.73, 1.21)) * 7.5 +
                    positionWS.y * 0.55
                );

                float leafWaveB = sin(
                    time * (leafSpeedMain * 1.43) +
                    dot(positionWS.xz, float2(1.17, -0.46)) * 9.0 +
                    positionWS.y * 1.25
                );

                // Дрібне швидке тремтіння.
                float leafFineA = sin(
                    time * leafSpeedFast +
                    dot(positionWS.xz, float2(-0.62, 1.36)) * 13.0 +
                    positionWS.y * 2.2
                );

                float leafFineB = sin(
                    time * (leafSpeedFast * 1.37) +
                    dot(positionWS.xz, float2(1.91, 0.27)) * 17.0
                );

                float broadFlutter = (leafWaveA + leafWaveB * 0.55) / 1.55;
                float fineFlutter = (leafFineA + leafFineB * 0.5) / 1.5;

                float fineMix = smoothstep(0.25, 0.85, wind01);

                float leafChaos = lerp(broadFlutter, fineFlutter, fineMix * 0.78);

                float flutterAmplitude =
                    g *
                    _LeafFlutter *
                    gust *
                    lerp(0.006, 0.023, wind01);

                flutterAmplitude = min(flutterAmplitude, 0.04);

                // Більше руху по напрямку вітру, менше вбік.
                positionWS.xz += windDir2  * leafChaos * flutterAmplitude * 0.72;
                positionWS.xz += windSide2 * leafChaos * flutterAmplitude * 0.28;

                // B — вертикальне дрібне тремтіння.
                float verticalWave = sin(
                    time * (leafSpeedFast * 0.72) +
                    positionWS.y * 5.2 +
                    dot(positionWS.xz, windDir2) * 0.5
                );

                float verticalStrength =
                    b *
                    _LeafFlutter *
                    gust *
                    lerp(0.002, 0.012, wind01);

                verticalStrength = min(verticalStrength, 0.02);

                positionWS.y += verticalWave * verticalStrength;

                return positionWS;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 positionOS = IN.positionOS.xyz;
                float3 normalOS = IN.normalOS;

                ApplyTreeBendOS(positionOS, normalOS, IN.color);

                float3 positionWS = TransformObjectToWorld(positionOS);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);

                positionWS = ApplyLeafWindWS(positionWS, IN.color);

                OUT.positionHCS = TransformWorldToHClip(positionWS);
                OUT.normalWS = normalize(normalWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.windMask = IN.color;

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                if (_DebugWindMask > 0.5)
                {
                    return half4(IN.windMask.rgb, 1);
                }

                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                half3 normalWS = normalize(IN.normalWS);
                Light mainLight = GetMainLight();

                half ndotl = saturate(dot(normalWS, mainLight.direction));

                half3 ambient = SampleSH(normalWS) + half3(_AmbientBoost, _AmbientBoost, _AmbientBoost);
                half3 lighting = ambient + mainLight.color.rgb * ndotl;

                half3 finalColor = baseTex.rgb * lighting;

                return half4(finalColor, baseTex.a);
            }

            ENDHLSL
        }
    }

    FallBack Off
}