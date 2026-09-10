using System;
using System.Collections.Generic;
using UnityEngine;

namespace MyGame.Wind
{
    /// <summary>
    /// Єдиний контролер вітру для bending-tree шейдера.
    /// Керує глобальними шейдерними властивостями (_WindDirection, _WindStrength,
    /// _WindSize, _WindSpeed) через перехід за кривою ease-in-out — тому будь-яка
    /// зміна має мʼякий старт І мʼяке завершення (повільно → швидко → повільно), без ривків.
    ///
    /// Вигин/нахил трунка ("lean/bend") у цьому шейдері = _WindStrength * _Bending_Strength,
    /// тому сила вигину наростає автоматично разом із strength — окремо матеріал чіпати не треба.
    ///
    /// ПРИМІТКА: якщо на сцені є старий WindManager — вимкни/видали його,
    /// щоб два скрипти не боролися за одні й ті самі глобальні властивості.
    /// </summary>
    [ExecuteAlways]
    [DisallowMultipleComponent]
    public class WindController : MonoBehaviour
    {
        // --- Глобальні властивості шейдера (ID кешуємо для швидкості) ---
        static readonly int ID_Dir = Shader.PropertyToID("_WindDirection");
        static readonly int ID_Strength = Shader.PropertyToID("_WindStrength");
        static readonly int ID_Size = Shader.PropertyToID("_WindSize");
        static readonly int ID_Speed = Shader.PropertyToID("_WindSpeed");
        static readonly int ID_Bend = Shader.PropertyToID("_Bending_Strength");

        [Serializable]
        public struct WindState
        {
            [Tooltip("Напрям вітру (X = світова X, Y = світова Z).")]
            public Vector2 direction;

            [Tooltip("Сила шуму крони / загальна сила вітру (_WindStrength). Вигин трунка росте від цього ж.")]
            [Min(0f)] public float strength;

            [Tooltip("Розмір хвилі (_WindSize). Менше = дрібні швидкі коливання, більше = довгі плавні хвилі.")]
            [Min(0f)] public float size;

            [Tooltip("Швидкість анімації вітру (_WindSpeed).")]
            [Min(0f)] public float speed;

            public static WindState Lerp(WindState a, WindState b, float t) => new WindState
            {
                direction = Vector2.Lerp(a.direction, b.direction, t),
                strength = Mathf.Lerp(a.strength, b.strength, t),
                size = Mathf.Lerp(a.size, b.size, t),
                speed = Mathf.Lerp(a.speed, b.speed, t),
            };
        }

        // ============================ ПРЕСЕТИ ============================
        [Header("── 3 СТУПЕНІ ВІТРУ ──")]
        public WindState calm = new WindState { direction = new Vector2(1, 0), strength = 0.18f, size = 1.30f, speed = 0.5f };
        public WindState medium = new WindState { direction = new Vector2(1, 0), strength = 0.60f, size = 1.00f, speed = 1.0f };
        public WindState extreme = new WindState { direction = new Vector2(1, 0), strength = 1.35f, size = 0.75f, speed = 1.7f };

        [Tooltip("Стан 'штиль' — куди йдемо при KillWind() / повному затуханні.")]
        public WindState zero = new WindState { direction = new Vector2(1, 0), strength = 0f, size = 1.2f, speed = 0.2f };

        // ============================ ПЛАВНІСТЬ ============================
        [Header("── ПЛАВНІСТЬ (головне проти ривків) ──")]
        [Tooltip("Тривалість переходу між пресетами, сек.")]
        [Min(0.01f)] public float presetSmoothTime = 1.5f;

        [Tooltip("Тривалість переходу при зупинці/затуханні вітру, сек.")]
        [Min(0.01f)] public float stopSmoothTime = 2.5f;

        [Tooltip("Форма переходу. За замовчуванням ease-in-out: повільний старт → розгін → повільний фініш. Саме це прибирає ривок на старті.")]
        public AnimationCurve easing = AnimationCurve.EaseInOut(0f, 0f, 1f, 1f);

        [Tooltip("Застосувати стартовий пресет при вмиканні.")]
        public bool applyOnEnable = true;

        [Tooltip("Який пресет вважати стартовим.")]
        public Preset startPreset = Preset.Calm;

        // ============================ ЖИВІСТЬ (пориви) ============================
        [Header("── ОРГАНІЧНІ ПОРИВИ (щоб не був статичним) ──")]
        [Tooltip("Додавати живий шум поверх сили/напряму — вітер 'дихає'.")]
        public bool turbulence = true;

        [Tooltip("Наскільки сильно пориви модулюють силу (0..1 від поточної strength).")]
        [Range(0f, 1f)] public float gustAmount = 0.25f;

        [Tooltip("Частота поривів (Гц-подібно). Менше = довгі рідкісні пориви.")]
        [Min(0.001f)] public float gustFrequency = 0.35f;

        [Tooltip("Легке похитування напряму від поривів (у градусах).")]
        [Range(0f, 45f)] public float directionSway = 6f;

        // ============================ ПЛАНУВАЛЬНИК ("з 5с до 10с") ============================
        [Header("── ЗАПЛАНОВАНИЙ ПОРИВ (таймлайн) ──")]
        [Tooltip("На якій секунді почати сильний вітер.")]
        [Min(0f)] public float scheduledStartTime = 5f;

        [Tooltip("На якій секунді завершити (повернутись до фонового стану).")]
        [Min(0f)] public float scheduledEndTime = 10f;

        [Tooltip("Який пресет вмикати на піку запланованого пориву.")]
        public Preset scheduledPeak = Preset.Extreme;

        [Tooltip("Фоновий стан до/після запланованого пориву.")]
        public Preset scheduledBase = Preset.Calm;

        [Tooltip("Час наростання до піку, сек.")]
        [Min(0.01f)] public float scheduledRampUp = 1.2f;

        [Tooltip("Час спаду після піку, сек (зазвичай довший — так натуральніше).")]
        [Min(0.01f)] public float scheduledRampDown = 3.0f;

        // ============================ РОЗІГРІВ (наростання) ============================
        [Header("── ПРОГРЕСИВНЕ НАРОСТАННЯ ──")]
        [Tooltip("Тривалість кожної сходинки Calm→Medium→Extreme, сек.")]
        [Min(0.1f)] public float buildupStep = 3f;

        // ============================ ЖИВИЙ СТАН (тільки для перегляду) ============================
        [Header("── ПОТОЧНИЙ СТАН (read-only) ──")]
        [SerializeField] WindState _current;

        public enum Preset { Calm, Medium, Extreme, Zero }

        // --- внутрішнє ---
        WindState _from;        // стан на початку переходу
        WindState _target;      // ціль переходу
        float _transDuration = 1.5f;
        float _transElapsed;
        bool _transitioning;
        float _lastRealtime;

        // Планувальник (мінімальний таймлайн, працює і в Edit, і в Play)
        [Serializable]
        struct Cue { public float time; public WindState state; public float smoothTime; }
        readonly List<Cue> _sequence = new List<Cue>();
        float _seqTime;
        int _seqIndex;
        bool _sequenceRunning;

        public WindState Current => _current;
        public bool SequenceRunning => _sequenceRunning;
        public float SequenceTime => _seqTime;
        public float CurrentStrength01 => extreme.strength > 0.0001f ? Mathf.Clamp01(_current.strength / extreme.strength) : 0f;

        // ------------------------------------------------------------------
        void OnEnable()
        {
            _lastRealtime = Time.realtimeSinceStartup;
            if (applyOnEnable)
                SnapTo(GetPreset(startPreset));
#if UNITY_EDITOR
            if (!Application.isPlaying)
                UnityEditor.EditorApplication.update += EditorTick;
#endif
        }

        void OnDisable()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.update -= EditorTick;
#endif
        }

        void Update()
        {
            if (Application.isPlaying)
                Tick(Time.deltaTime);
        }

#if UNITY_EDITOR
        // У Edit-режимі Update викликається нерегулярно — тому крутимо власний тік
        // через EditorApplication.update, щоб превʼю було таким же плавним, як у грі.
        void EditorTick()
        {
            if (Application.isPlaying) return;
            float now = Time.realtimeSinceStartup;
            float dt = Mathf.Clamp(now - _lastRealtime, 0f, 0.1f);
            _lastRealtime = now;
            Tick(dt);
            if (_sequenceRunning || IsMoving())
                UnityEditor.SceneView.RepaintAll();
        }
#endif

        bool IsMoving() => _transitioning;

        // ------------------------------------------------------------------
        void Tick(float dt)
        {
            if (dt <= 0f) return;

            AdvanceSequence(dt);

            if (_transitioning)
            {
                _transElapsed += dt;
                float u = _transDuration > 0.0001f ? Mathf.Clamp01(_transElapsed / _transDuration) : 1f;
                float e = easing != null ? easing.Evaluate(u) : u;   // ease-in-out: плавний старт І фініш
                _current = WindState.Lerp(_from, _target, e);
                if (u >= 1f)
                {
                    _current = _target;
                    _transitioning = false;
                }
            }

            Apply(_current);
        }

        void AdvanceSequence(float dt)
        {
            if (!_sequenceRunning) return;
            _seqTime += dt;
            while (_seqIndex < _sequence.Count && _seqTime >= _sequence[_seqIndex].time)
            {
                var cue = _sequence[_seqIndex];
                BeginTransition(cue.state, cue.smoothTime);
                _seqIndex++;
            }
            // Усі к'ю роздані — секвенція завершена; останній перехід доїжджає сам через _transitioning.
            if (_seqIndex >= _sequence.Count)
                _sequenceRunning = false;
        }

        void BeginTransition(WindState target, float duration)
        {
            _from = _current;
            _target = target;
            _transDuration = Mathf.Max(0.01f, duration);
            _transElapsed = 0f;
            _transitioning = true;
        }

        // ------------------------------------------------------------------
        void Apply(WindState s)
        {
            Vector2 dir = s.direction;
            float strength = Mathf.Max(0f, s.strength);

            if (turbulence)
            {
                float t = Application.isPlaying ? Time.time : Time.realtimeSinceStartup;
                // Пориви сили: 0..1 шум, зміщений навколо базового рівня.
                float n = Mathf.PerlinNoise(t * gustFrequency, 0.123f) * 2f - 1f;
                strength = Mathf.Max(0f, strength * (1f + n * gustAmount));

                if (directionSway > 0f && dir.sqrMagnitude > 0.0001f)
                {
                    float swayN = Mathf.PerlinNoise(0.777f, t * gustFrequency) * 2f - 1f;
                    float ang = swayN * directionSway * Mathf.Deg2Rad;
                    float cs = Mathf.Cos(ang), sn = Mathf.Sin(ang);
                    dir = new Vector2(dir.x * cs - dir.y * sn, dir.x * sn + dir.y * cs);
                }
            }

            Shader.SetGlobalVector(ID_Dir, new Vector4(dir.x, dir.y, 0f, 0f));
            Shader.SetGlobalFloat(ID_Strength, strength);
            Shader.SetGlobalFloat(ID_Size, Mathf.Max(0f, s.size));
            Shader.SetGlobalFloat(ID_Speed, Mathf.Max(0f, s.speed));
        }

        // ================= ПУБЛІЧНЕ API (для кнопок / коду) =================

        /// <summary>Плавно перейти до пресета.</summary>
        public void SetTarget(WindState state, float smoothTime)
        {
            CancelSequence();
            BeginTransition(state, smoothTime);
        }

        /// <summary>Миттєво встановити стан (без переходу).</summary>
        public void SnapTo(WindState state)
        {
            CancelSequence();
            _current = _from = _target = state;
            _transitioning = false;
            Apply(_current);
        }

        public void GoCalm() => SetTarget(calm, presetSmoothTime);
        public void GoMedium() => SetTarget(medium, presetSmoothTime);
        public void GoExtreme() => SetTarget(extreme, presetSmoothTime);
        public void KillWind() => SetTarget(zero, stopSmoothTime);

        /// <summary>Прогресивне наростання: Calm → Medium → Extreme, кожна сходинка buildupStep секунд.</summary>
        public void PlayBuildup()
        {
            _sequence.Clear();
            _sequence.Add(new Cue { time = 0f, state = calm, smoothTime = buildupStep * 0.9f });
            _sequence.Add(new Cue { time = buildupStep, state = medium, smoothTime = buildupStep * 0.9f });
            _sequence.Add(new Cue { time = buildupStep * 2f, state = extreme, smoothTime = buildupStep * 0.9f });
            StartSequence();
        }

        /// <summary>Затухання назад: Extreme → Medium → Calm → штиль.</summary>
        public void PlayCalmdown()
        {
            _sequence.Clear();
            _sequence.Add(new Cue { time = 0f, state = medium, smoothTime = buildupStep });
            _sequence.Add(new Cue { time = buildupStep, state = calm, smoothTime = buildupStep });
            _sequence.Add(new Cue { time = buildupStep * 2f, state = zero, smoothTime = buildupStep });
            StartSequence();
        }

        /// <summary>
        /// Запланований порив за таймлайном: тримати фон, з scheduledStartTime підняти до піку,
        /// на scheduledEndTime плавно повернути до фону. Точно як "сильний вітер з 5с, завершити на 10с".
        /// </summary>
        public void ScheduleGust()
        {
            WindState baseState = GetPreset(scheduledBase);
            WindState peakState = GetPreset(scheduledPeak);
            float start = Mathf.Max(0f, scheduledStartTime);
            float end = Mathf.Max(start + 0.01f, scheduledEndTime);

            _sequence.Clear();
            _sequence.Add(new Cue { time = 0f, state = baseState, smoothTime = scheduledRampUp });
            _sequence.Add(new Cue { time = start, state = peakState, smoothTime = scheduledRampUp });
            _sequence.Add(new Cue { time = end, state = baseState, smoothTime = scheduledRampDown });
            StartSequence();
        }

        void StartSequence()
        {
            _sequence.Sort((a, b) => a.time.CompareTo(b.time));
            _seqTime = 0f;
            _seqIndex = 0;
            _sequenceRunning = _sequence.Count > 0;
            _lastRealtime = Time.realtimeSinceStartup;
        }

        public void CancelSequence()
        {
            _sequenceRunning = false;
            _sequence.Clear();
            _seqIndex = 0;
            _seqTime = 0f;
        }

        WindState GetPreset(Preset p)
        {
            switch (p)
            {
                case Preset.Calm: return calm;
                case Preset.Medium: return medium;
                case Preset.Extreme: return extreme;
                default: return zero;
            }
        }

        void OnValidate()
        {
            // Живий відгук при правці чисел в інспекторі (Edit-режим).
            if (!Application.isPlaying && isActiveAndEnabled)
                Apply(_current);
        }
    }
}
