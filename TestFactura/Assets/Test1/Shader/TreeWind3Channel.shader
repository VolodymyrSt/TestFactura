// =============================================================================
//  Custom/TreeWind3Channel  (URP)
//
//  Вітер керується ВИКЛЮЧНО vertex color:
//      R = вага основного вигину. 0 біля кореня -> 1 на кінчиках.
//      G = вага флаттера листя.
//      B = вага коливання гілок.
//
//  R — це ІЄРАРХІЧНИЙ канал: його градієнт має бути нанесений на весь меш,
//  включно з гілками ТА листям. Інакше листя не має ваги вигину, стовбур
//  гнеться, а крона лишається на місці — і дерево розривається.
//
//      стовбур  = чорний -> червоний   (R градієнт)
//      гілки    = фіолетовий           (R + B)
//      листя    = жовтий               (R + G)   <-- НЕ чистий зелений
//
//  Якщо листя вже пофарбоване чистим зеленим, увімкніть _InheritMotion —
//  тоді листя успадкує рух стовбура/гілок з вагою 1. Це рятує від розриву,
//  але градієнта за висотою у крони не буде.
//
//  ВАЖЛИВО: якщо у меша немає каналу COLOR, Unity віддає білий (1,1,1,1)
//  і дерево буде трясти цілком. База стовбура має бути чорною.
// =============================================================================
Shader "Custom/TreeWind3Channel"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap ("Base Texture", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Wind)]
        _WindDirection ("Wind Direction World Space", Vector) = (1,0,0,0)
        _WindSpeed ("Wind Speed", Float) = 1.0
        _BranchLeadTime ("Trunk Lag Seconds", Float) = 0.5
        _PhaseVariation ("Per Object Phase Variation", Range(0,4)) = 1.0

        [Header(Gust)]
        _GustStrength ("Gust Amount", Range(0,1)) = 0.5
        _GustSpeed ("Gust Speed", Float) = 0.15

        [Header(Lean)]
        [Toggle(_LEAN_WIND)] _LeanIntoWind ("Lean Into Wind", Float) = 1.0
        _WindLean ("Wind Lean Weight", Range(0,1)) = 0.3
        // Залишкове ТРЕМТІННЯ — не зникає навіть коли дерево «залипло» (lean=1),
        // тож стовбур і гілки дрижать/гойдаються навколо пози, а не стоять
        // мертво. Це турбулентність. 0 = повна фіксація, 0.1-0.2 = живо.
        _Turbulence ("Turbulence (alive when pinned)", Range(0,0.5)) = 0.12
        _TurbulenceSpeed ("Turbulence Speed", Float) = 3.0

        [Header(Channel Mode)]
        [Toggle(_INHERIT_MOTION)] _InheritMotion ("Leaves Inherit Trunk And Branch Motion", Float) = 1.0

        [Header(Trunk    vertex color R)]
        // ПРЯМИЙ НАХИЛ, не оберт. Це макс. бічний зсув верхівки в ОДИНИЦЯХ
        // МЕША (там, де R=1). Зсув КОЖНОЇ вершини = _TrunkStrength * R, тож
        // нахил лінійний рівно настільки, наскільки лінійний R за висотою.
        // R МУСИТЬ бути пофарбований лінійно ЗА ВИСОТОЮ стовбура (0 біля кореня
        // -> 1 на верхівці), а НЕ за довжиною вигнутої гілки: інакше на згині,
        // де висота майже не росте, а R усе одно доходить до 1, верхівку
        // виносить убік далі за пряме продовження стовбура (дуга).
        // Це дерево ~470 юнітів заввишки, тож 20-50 = помітний нахил.
        _TrunkStrength ("Trunk Lean Distance (mesh units)", Float) = 30
        _TrunkSpeed ("Trunk Speed", Float) = 0.5
        _BendSmoothness ("Bend Smoothness (0=hard corner, 1=soft arc)", Range(0,1)) = 0.5

        [Header(Branches    vertex color B)]
        // Кут ГОЙДАННЯ гілки навколо вертикальної осі стовбура (радіани).
        // Оберт -> без розтягу. 0.2 рад ~ 11 градусів змаху вбік.
        _BranchStrength ("Branch Swing radians", Range(0,1)) = 0.2
        _BranchSpeed ("Branch Speed", Float) = 1.5
        // Розкид фази за ВИСОТОЮ (десинхрон ярусів). Малий, щоб фаза майже не
        // мінялась уздовж однієї гілки, інакше гілку трохи скручує.
        _BranchPhaseSpread ("Branch Phase Spread per unit height", Range(0,0.2)) = 0.03

        [Header(Flutter    vertex color G)]
        // Амплітуда в ОДИНИЦЯХ МЕША (метрах), не в умовних попугаях.
        // Листок тут ~0.2 м, тож 1.16 — це зміщення у 5 розмірів листка.
        _FlutterStrength ("Flutter Strength meters", Range(0,0.5)) = 0.05
        _FlutterSpeed ("Flutter Speed", Float) = 8.0
        // Додає повершинний розкид фази. Тримайте 0, якщо листя flat-shaded.
        _FlutterPhaseSpread ("Flutter Phase Spread", Range(0,3)) = 0.0

        [Header(Leaf Lighting)]
        _Translucency ("Translucency", Range(0,2)) = 0.4
    }

    SubShader
    {
        Tags
        {
            "RenderType"      = "TransparentCutout"
            "RenderPipeline"  = "UniversalPipeline"
            "Queue"           = "AlphaTest"
            "IgnoreProjector" = "True"
        }
        LOD 200
        Cull Off

        // ---------------------------------------------------------------------
        // Спільний код для всіх пасів. Одна CBUFFER + одна реалізація вітру =
        // SRP Batcher сумісність і гарантія, що тінь/глибина збігаються з мешем.
        // ---------------------------------------------------------------------
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            float4 _WindDirection;
            half   _Cutoff;
            float  _WindSpeed;
            float  _BranchLeadTime;
            float  _PhaseVariation;
            float  _GustStrength;
            float  _GustSpeed;
            float  _WindLean;
            float  _Turbulence;
            float  _TurbulenceSpeed;
            float  _TrunkStrength;
            float  _TrunkSpeed;
            float  _BendSmoothness;
            float  _BranchStrength;
            float  _BranchSpeed;
            float  _BranchPhaseSpread;
            float  _FlutterStrength;
            float  _FlutterSpeed;
            float  _FlutterPhaseSpread;
            half   _Translucency;
        CBUFFER_END

        // Глобальна сила вітру 0..1. Ставить GlobalWindManager через
        // Shader.SetGlobalFloat("_GlobalWindStrength", ...). Оголошено ПОЗА
        // UnityPerMaterial, бо це глобальний, а не матеріальний параметр
        // (у CBUFFER він зламав би SRP Batcher). Якщо ніхто його не пише —
        // дорівнює 0, і поведінка така сама, як без сили вітру.
        float _GlobalWindStrength;

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        // Обертання навколо осі. sin/cos рахуються один раз ззовні.
        float3 RotateAxis(float3 p, float3 axis, float s, float c)
        {
            return p * c + cross(axis, p) * s + axis * (dot(axis, p) * (1.0 - c));
        }

        // ---------------------------------------------------------------------
        //  Джерела зсуву фази.
        //
        //  Ключове правило: якщо фаза відрізняється між вершинами ОДНОГО листка,
        //  вони роз'їжджаються і листок розтягується. Величина розриву =
        //  амплітуда * градієнт фази * розмір листка. Саме тому позиційний хеш
        //  тут майже не використовується.
        // ---------------------------------------------------------------------

        // Позиційна фаза. КЛЮЧОВЕ: дві вершини в ОДНІЙ точці (спільне ребро)
        // отримують ІДЕНТИЧНУ фазу, тому грані не розходяться. Раніше фаза
        // бралася з нормалі — а в цій кроні в одній точці сходяться вершини з
        // протилежними нормалями (жорсткі краї), тож кожне ребро тріскалося.
        float PhaseFromPosition(float3 posOS)
        {
            return dot(posOS, float3(0.7, 1.3, 0.5));
        }

        // ---------------------------------------------------------------------
        //  Головна функція вітру. Нормаль обертається разом з позицією,
        //  інакше освітлення "відклеюється" від геометрії під час хитання.
        // ---------------------------------------------------------------------
        void ApplyWind(inout float3 positionOS, inout float3 normalOS, half4 vertexColor)
        {
            half r = vertexColor.r;
            half g = vertexColor.g;
            half b = vertexColor.b;

            // Стовбурний згин (оберт навколо БАЗИ дерева) ЗАВЖДИ керується
            // гладким R-градієнтом. Раніше в режимі INHERIT тут стояло
            // max(r,g,b): на гілці маска стрибала 0.5 -> 1.0 уздовж гілки, а
            // плече оберту від бази = сотні юнітів, тож гілку розтягувало.
            // Локальний рух гілок/листя тепер дає окремий блок нижче зі своїм
            // півотом, тому глобальний згин більше не мусить їх "тягнути".
            half bendMask = r;
        #if defined(_INHERIT_MOTION)
            half branchMask = max(b, g);   // гілки + зелене листя — локальний змах
        #else
            half branchMask = b;
        #endif
            half flutterMask = g;

            // Нічого не пофарбовано -> вершина статична.
            if (bendMask + flutterMask + branchMask <= 0.001)
                return;

            float3 srcOS = positionOS;

            // --- базис вітру в object space --------------------------------
            // Переводимо напрямок у локальний простір, тому дерево можна
            // вільно обертати і ставити на схил — вітер лишається світовим.
            float3 windWS = _WindDirection.xyz;
            float wLenSq = dot(windWS, windWS);
            windWS = (wLenSq > 1e-6) ? windWS * rsqrt(wLenSq) : float3(1, 0, 0);

            float3 windOS = TransformWorldToObjectDir(windWS);
            float3 upOS   = TransformWorldToObjectDir(float3(0, 1, 0));

            // Вісь вигину = горизонтальна вісь, перпендикулярна вітру.
            // Вона ж використовується як бічний напрямок для флаттера.
            float3 bendAxis = cross(upOS, windOS);
            float bLenSq = dot(bendAxis, bendAxis);
            bendAxis = (bLenSq > 1e-6) ? bendAxis * rsqrt(bLenSq) : float3(0, 0, 1);

            // --- фаза на об'єкт --------------------------------------------
            // Без цього цілий ліс хитається синхронно, як один організм.
            float4x4 m = GetObjectToWorldMatrix();
            float3 pivotWS = float3(m._m03, m._m13, m._m23);
            float objPhase = dot(pivotWS, float3(0.37, 0.11, 0.73)) * _PhaseVariation;

            float t = _Time.y * _WindSpeed;

            // --- пориви ------------------------------------------------------
            // Повільна огинаюча амплітуди: рух то підсилюється, то стихає.
            float gust = 0.5 + 0.5 * sin(t * _GustSpeed + objPhase * 0.5);
            float amp  = lerp(1.0, gust, _GustStrength);

            // Вага «залипання» за вітром. Базово = _WindLean, але при сильному
            // вітрі (глобальна сила -> 1) прямує до 1. Хвиля нижче має вигляд
            // leanW + (1-leanW)*sin, тож:
            //   leanW = 0   -> симетричне хитання (sin, туди-сюди)
            //   leanW = 0.5 -> завжди за вітром, пульсує 0..макс
            //   leanW = 1   -> КОНСТАНТА = дерево ФІКСУЄТЬСЯ в точці нахилу
            // Діє однаково на стовбур і на гілки.
            float windStrength = saturate(_GlobalWindStrength);
            float leanW = saturate(lerp(_WindLean, 1.0, windStrength));

            // ---------- 1. СТОВБУР (vertex color R) — ПРЯМИЙ НАХИЛ ----------
            // Раніше кут ОБЕРТУ множився на R, а R плавно росте по висоті, тож
            // кожна секція оберталась на свій кут -> стовбур вигинало дугою
            // (C/S). Тепер це ПРЯМИЙ нахил: горизонтальний зсув уздовж вітру,
            // пропорційний R. R лінійно росте від 0 (середина = точка півота)
            // до 1 (верхівка), тому зсув лінійний по висоті -> стовбур лишається
            // ПРЯМИМ і просто нахиляється. Нижче R=0 -> основа стоїть рівно.
            //
            // Зсув фази = затримка стовбура на _BranchLeadTime секунд.
            float trunkPhase = t * _TrunkSpeed
                             - _BranchLeadTime * _TrunkSpeed * _WindSpeed
                             + objPhase;
            float trunkSin = sin(trunkPhase);

            #if defined(_LEAN_WIND)
                // leanW -> 1 при сильному вітрі => основна хвиля -> 1 => стовбур
                // прямує в точку максимального нахилу...
                float trunkWave = leanW + (1.0 - leanW) * trunkSin;

                // ...але додаємо ТРЕМТІННЯ (турбулентність) — воно НЕ множиться
                // на (1-leanW), тож лишається навіть при lean=1. Тому «залипле»
                // дерево не мертве, а дрижить навколо нахилу. Два несинхронні
                // синуси вищої частоти = живий, неперіодичний тремор.
                // Тремор тільки при Lean into wind — без нього дерево лише
                // симетрично хитається (sin) і не дьоргається.
                float trTremor = sin(t * _TurbulenceSpeed + objPhase * 1.7)
                               + 0.5 * sin(t * _TurbulenceSpeed * 2.3 + objPhase * 0.7);
                trunkWave += _Turbulence * amp * trTremor;
            #else
                float trunkWave = trunkSin;
            #endif

            // Горизонтальний напрямок вітру = напрямок нахилу.
            float3 leanDir = windOS - upOS * dot(windOS, upOS);
            float leanLen  = length(leanDir);
            leanDir = (leanLen > 1e-4) ? leanDir / leanLen : bendAxis;

            // R пофарбований 0 у нижній половині стовбура й ЛІНІЙНО росте до 1
            // у верхній (paint "від середини"). Прямий зсув, пропорційний саме
            // R, дає в точці, де R відривається від нуля, ЗЛАМ: низ вертикальний
            // (R=0, зсув=0), верх нахилений (R лінійний, зсув лінійний). Позиція
            // неперервна, а от ДОТИЧНА — ні: похідна зсуву стрибає з 0 до k*R' ->
            // гострий кут рівно на середині. Саме це і є "різкий перехід".
            //
            // _BendSmoothness застосовує ease-in (степінь) до R перед зсувом.
            // При степені >1 похідна зсуву по висоті на стику (R=0) = 0, тож
            // дотична стає НЕПЕРЕРВНОЮ -> замість коліна виходить ПЛАВНА дуга:
            // від вертикалі на середині вона поступово доростає до повного
            // нахилу вгорі. R=1 (верхівка) лишається 1, тому амплітуда нахилу
            // кінчика НЕ міняється — гладшає тільки перехід.
            //   _BendSmoothness = 0 -> степінь 1 -> лінійно (старий різкий злам)
            //   _BendSmoothness = 1 -> степінь 3 -> м'який вхід у вигин
            float bendExp    = lerp(1.0, 3.0, saturate(_BendSmoothness));
            float bendShaped = pow(max(bendMask, 0.0), bendExp);

            // Зсув у ОДИНИЦЯХ МЕША, пропорційний згладженому R. Нормаль не
            // чіпаємо: нахил малий, освітлення кори практично не змінюється.
            float trunkLean = trunkWave * _TrunkStrength * amp * bendShaped;
            positionOS += leanDir * trunkLean;

            // ---------- 2. ГІЛКИ (vertex color B) — ЗГИН ЗА ВІТРОМ ----------
            // Гілки гнуться В БІК ВІТРУ (туди, куди хилиться стовбур), а не по
            // колу. Робимо це ОБЕРТОМ навколо ВЕРТИКАЛЬНОЇ осі стовбура (upOS),
            // тому радіус кожної вершини зберігається -> НЕ розтягує і вершини
            // не находять одна на одну (рух як тверде тіло).
            //
            // КЛЮЧОВЕ: кут ЗНАКОВИЙ за орієнтацією гілки. turnSign =
            // sin(кута від гілки до вітру) — гілка повертається в той бік, де
            // цей кут зменшується, тобто ДО вітру. Тому гілки з обох боків
            // сходяться за вітром, а не крутяться всі в один бік (орбіта).
            // Гілка вздовж вітру майже не рухається, поперек — найбільше.
            float3 windFlat = windOS - upOS * dot(windOS, upOS);
            float wfLen = length(windFlat);
            windFlat = (wfLen > 1e-4) ? windFlat / wfLen : bendAxis;

            float3 armFlat = positionOS - upOS * dot(positionOS, upOS); // горизонт. виліт гілки від осі
            float  reach   = length(armFlat);
            float3 armDir  = (reach > 1e-4) ? armFlat / reach : windFlat;

            // + => поворот навколо upOS наближає гілку до напрямку вітру.
            float turnSign = dot(cross(armDir, windFlat), upOS);

            // Хвиля з ухилом за вітром (як у стовбура): при _LEAN_WIND гілки
            // тримаються відхиленими за вітром і ще пульсують від поривів.
            float branchPhase = t * _BranchSpeed
                              + objPhase
                              + srcOS.y * _BranchPhaseSpread;   // десинхрон ярусів (тримати малим)
            float branchSin = sin(branchPhase);
            #if defined(_LEAN_WIND)
                // Той самий leanW: при сильному вітрі -> 1, гілки прямують до
                // пози «відхилені за вітром».
                float branchWave = leanW + (1.0 - leanW) * branchSin;

                // Тремтіння гілок — не зникає при lean=1, тож вони гнуться за
                // вітром, там «стають», але дрижать назад-вперед. Своя фаза
                // (+ висота), щоб тремтіли не в унісон зі стовбуром. Тільки при
                // Lean into wind — без нього гілки лише хитаються симетрично.
                float brTremor = sin(t * _TurbulenceSpeed * 1.3 + objPhase * 2.1 + srcOS.y * 0.02)
                               + 0.5 * sin(t * _TurbulenceSpeed * 2.7 + objPhase * 1.1);
                branchWave += _Turbulence * amp * brTremor;
            #else
                float branchWave = branchSin;
            #endif

            float branchAngle = branchWave * _BranchStrength * amp * branchMask * turnSign;
            float brs, brc;
            sincos(branchAngle, brs, brc);
            positionOS = RotateAxis(positionOS, upOS, brs, brc);
            normalOS   = RotateAxis(normalOS,   upOS, brs, brc);

            // ---------- 3. ФЛАТТЕР ЛИСТЯ (vertex color G) -------------------
            // Дві несинхронні хвилі: вбік (по вітру, bendAxis) і вертикально
            // (upOS, листок "плескає"). Обидва напрямки — СТАЛІ осі об'єкта.
            //
            // І фаза, і напрямок зсуву НЕ залежать від повершинної нормалі.
            // У цій кроні в одній точці сходяться вершини з протилежними
            // нормалями (до 169°). Стара формула штовхала їх уздовж власних
            // нормалей у різні боки й давала їм різну фазу -> кожне жорстке
            // ребро розходилось, і крона рвалась на клапті. Тепер вершини зі
            // спільною позицією дістають ІДЕНТИЧНИЙ зсув -> ребра зварені,
            // а різні листки все одно колишуться в різній фазі (позиція різна).
            float flutterPhase = t * _FlutterSpeed
                               + PhaseFromPosition(srcOS) * (1.0 + _FlutterPhaseSpread)
                               + objPhase;
            float f1 = sin(flutterPhase);
            float f2 = sin(flutterPhase * 1.7 + 1.3);
            positionOS += (bendAxis * f1 + upOS * (f2 * 0.5))
                        * (_FlutterStrength * flutterMask * amp);
        }
        ENDHLSL

        // =====================================================================
        //  FORWARD
        // =====================================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            AlphaToMask On

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex LitVert
            #pragma fragment LitFrag

            #pragma shader_feature_local _LEAN_WIND
            #pragma shader_feature_local _INHERIT_MOTION

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                half3  normalWS    : TEXCOORD2;
                half4  fogAndVertexLight : TEXCOORD3; // x = fog, yzw = vertex lights
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD4;
            #endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings LitVert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionOS = IN.positionOS.xyz;
                float3 normalOS   = IN.normalOS;
                ApplyWind(positionOS, normalOS, IN.color);

                VertexPositionInputs posInputs  = GetVertexPositionInputs(positionOS);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(normalOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = normInputs.normalWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);

                half3 vertexLight = VertexLighting(posInputs.positionWS, normInputs.normalWS);
                half  fogFactor   = ComputeFogFactor(posInputs.positionCS.z);
                OUT.fogAndVertexLight = half4(fogFactor, vertexLight);

            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                OUT.shadowCoord = GetShadowCoord(posInputs);
            #endif
                return OUT;
            }

            half4 LitFrag(Varyings IN, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(texColor.a - _Cutoff);

                // Cull Off -> задні грані мають вивернуту нормаль. Без цього
                // половина листя завжди темна.
                half3 normalWS = normalize(IN.normalWS);
                normalWS *= IS_FRONT_VFACE(facing, 1.0h, -1.0h);

                InputData inputData = (InputData)0;
                inputData.positionWS      = IN.positionWS;
                inputData.normalWS        = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                inputData.shadowCoord = IN.shadowCoord;
            #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                inputData.shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
            #else
                inputData.shadowCoord = float4(0, 0, 0, 0);
            #endif
                inputData.fogCoord                = IN.fogAndVertexLight.x;
                inputData.vertexLighting          = IN.fogAndVertexLight.yzw;
                inputData.bakedGI                 = SampleSH(normalWS); // дерева динамічні -> probes
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionHCS);
                inputData.shadowMask              = half4(1, 1, 1, 1);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo     = texColor.rgb;
                surfaceData.alpha      = 1.0h;
                surfaceData.smoothness = 0.0h;
                surfaceData.occlusion  = 1.0h;

                half4 color = UniversalFragmentPBR(inputData, surfaceData);

                // Просвічування листя замість старого max(color, albedo * 0.3):
                // світло, що проходить крізь листок у бік камери.
                Light mainLight = GetMainLight(inputData.shadowCoord);
                half backLight = saturate(dot(inputData.viewDirectionWS, -mainLight.direction));
                half atten = lerp(1.0h, mainLight.shadowAttenuation, 0.5h) * mainLight.distanceAttenuation;
                color.rgb += texColor.rgb * mainLight.color
                           * (backLight * backLight * _Translucency * atten);

                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                color.a   = texColor.a; // для AlphaToMask
                return color;
            }
            ENDHLSL
        }

        // =====================================================================
        //  SHADOW CASTER
        // =====================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag

            #pragma shader_feature_local _LEAN_WIND
            #pragma shader_feature_local _INHERIT_MOTION
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings ShadowVert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                float3 positionOS = IN.positionOS.xyz;
                float3 normalOS   = IN.normalOS;
                ApplyWind(positionOS, normalOS, IN.color);

                float3 positionWS = TransformObjectToWorld(positionOS);
                float3 normalWS   = TransformObjectToWorldNormal(normalOS);

                // Точкові/спот-джерела мають власний напрямок на вершину,
                // інакше bias рахується неправильно і тінь "відривається".
            #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirWS = _LightDirection;
            #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
            #endif

                OUT.positionHCS = positionCS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(texColor.a - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        // =====================================================================
        //  DEPTH ONLY  — потрібен для depth texture, SSAO, DoF, soft particles.
        //  Без цього паса дерево або зникає з глибини, або її дані не збігаються
        //  з деформованим мешем.
        // =====================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthVert
            #pragma fragment DepthFrag

            #pragma shader_feature_local _LEAN_WIND
            #pragma shader_feature_local _INHERIT_MOTION
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthVert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionOS = IN.positionOS.xyz;
                float3 normalOS   = IN.normalOS;
                ApplyWind(positionOS, normalOS, IN.color);

                OUT.positionHCS = TransformObjectToHClip(positionOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 DepthFrag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(texColor.a - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        // =====================================================================
        //  DEPTH NORMALS — для SSAO та ефектів, що читають _CameraNormalsTexture.
        // =====================================================================
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthNormalsVert
            #pragma fragment DepthNormalsFrag

            #pragma shader_feature_local _LEAN_WIND
            #pragma shader_feature_local _INHERIT_MOTION
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                half3  normalWS    : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthNormalsVert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionOS = IN.positionOS.xyz;
                float3 normalOS   = IN.normalOS;
                ApplyWind(positionOS, normalOS, IN.color);

                OUT.positionHCS = TransformObjectToHClip(positionOS);
                OUT.normalWS    = TransformObjectToWorldNormal(normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 DepthNormalsFrag(Varyings IN, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                clip(texColor.a - _Cutoff);

                half3 normalWS = normalize(IN.normalWS);
                normalWS *= IS_FRONT_VFACE(facing, 1.0h, -1.0h);
                return half4(normalWS, 0.0h);
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}