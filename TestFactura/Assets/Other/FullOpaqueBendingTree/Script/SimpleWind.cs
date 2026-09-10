using System.Collections.Generic;
using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

namespace MyGame.Wind
{
    /// <summary>
    /// Контролер вітру для шейдера Custom/TreeWind3Channel.
    /// Два набори головних значень (Breeze / Storm). Кнопка Storm лерпить їх
    /// ПОЕТАПНО: спершу Noise (flutter), потім Bend (trunk+branch), у кінці Lean
    /// (windLean + globalWindStrength). Решта параметрів (швидкості, гаст,
    /// турбулентність) — на матеріалі, скрипт їх не чіпає.
    /// </summary>
    [ExecuteAlways]
    public class SimpleWind : MonoBehaviour
    {
        [System.Serializable]
        public class WindPreset
        {
            [Tooltip("Noise: сила флаттеру листя (_FlutterStrength).")]
            [Range(0, 0.5f)] public float flutter = 0.02f;

            [Tooltip("Bend: сила нахилу стовбура (_TrunkStrength).")]
            public float trunk = 0.2f;
            [Tooltip("Bend: змах гілок (_BranchStrength).")]
            [Range(0, 1)] public float branch = 0.1f;

            [Tooltip("Lean: залипання за вітром (_WindLean).")]
            [Range(0, 1)] public float lean = 0.1f;
            [Tooltip("Lean: глобальна сила вітру (_GlobalWindStrength).")]
            [Range(0, 1)] public float global = 0f;
        }

        [Header("Матеріали дерев (кнопка нижче заповнить)")]
        public List<Material> targetMaterials = new List<Material>();

        [Header("Напрям вітру у світі (X, Y, Z)")]
        public Vector3 windDirection = new Vector3(0f, 0f, 1f);

        [Header("Синхронність дерев")]
        [Tooltip("_PhaseVariation для ВСІХ дерев одразу. 0 = усі рухаються синхронно; більше = природний різнобій.")]
        [Range(0f, 4f)] public float phaseVariation = 0f;

        [Header("🍃 BREEZE")]
        public WindPreset breeze = new WindPreset();

        [Header("🌪 STORM")]
        public WindPreset storm = new WindPreset { flutter = 0.05f, trunk = 0.9f, branch = 0.5f, lean = 0.6f, global = 1f };

        [Header("Тайминги фаз, сек (start = коли почати, dur = скільки лерпити)")]
        public float noiseStart = 0f;    public float noiseDur = 1.5f;
        public float branchStart = 0.8f; public float branchDur = 1.5f;   // гілки — раніше
        public float trunkStart = 1.8f;  public float trunkDur = 2.0f;    // стовбур — пізніше
        public float leanStart = 3.0f;   public float leanDur = 2.2f;

        const string KW_LEAN = "_LEAN_WIND";
        static readonly int ID_Global = Shader.PropertyToID("_GlobalWindStrength");

        [SerializeField] WindPreset _current = new WindPreset();
        readonly WindPreset _from = new WindPreset();
        bool _playing, _toStorm;
        float _clock, _lastTime;

        public bool IsPlaying => _playing;
        public float Progress => Mathf.Clamp01(_clock / Mathf.Max(0.01f, TotalDuration()));

        [ContextMenu("→ Storm")] public void ToStorm() => Play(true);
        [ContextMenu("→ Breeze")] public void ToBreeze() => Play(false);

        void Play(bool toStorm)
        {
            EnsureMaterials();
            SetupMaterials();
            Copy(_from, _current);
            _toStorm = toStorm;
            _clock = 0f;
            _playing = true;
            _lastTime = Time.realtimeSinceStartup;
            Debug.Log($"[SimpleWind] → {(toStorm ? "Storm" : "Breeze")}. Матеріалів: {targetMaterials.Count}", this);
        }

        float TotalDuration() => Mathf.Max(
            Mathf.Max(noiseStart + noiseDur, branchStart + branchDur),
            Mathf.Max(trunkStart + trunkDur, leanStart + leanDur));

        static float Phase(float clock, float start, float dur)
        {
            if (dur <= 0.0001f) return clock >= start ? 1f : 0f;
            float t = Mathf.Clamp01((clock - start) / dur);
            return t * t * t * (t * (t * 6f - 15f) + 10f);   // smootherstep
        }

        void Step(float dt)
        {
            if (_playing)
            {
                _clock += dt;
                float T = TotalDuration();

                float tN, tBr, tTr, tL;
                if (_toStorm)
                {
                    tN = Phase(_clock, noiseStart, noiseDur);
                    tBr = Phase(_clock, branchStart, branchDur);
                    tTr = Phase(_clock, trunkStart, trunkDur);
                    tL = Phase(_clock, leanStart, leanDur);
                }
                else // Breeze: у зворотному порядку (Lean відпускає першим)
                {
                    tL = Phase(_clock, T - (leanStart + leanDur), leanDur);
                    tTr = Phase(_clock, T - (trunkStart + trunkDur), trunkDur);
                    tBr = Phase(_clock, T - (branchStart + branchDur), branchDur);
                    tN = Phase(_clock, T - (noiseStart + noiseDur), noiseDur);
                }

                WindPreset to = _toStorm ? storm : breeze;
                _current.flutter = Mathf.Lerp(_from.flutter, to.flutter, tN);
                _current.branch = Mathf.Lerp(_from.branch, to.branch, tBr);
                _current.trunk = Mathf.Lerp(_from.trunk, to.trunk, tTr);
                _current.lean = Mathf.Lerp(_from.lean, to.lean, tL);
                _current.global = Mathf.Lerp(_from.global, to.global, tL);

                if (_clock >= T) _playing = false;
            }
            Apply(_current);
        }

        static void Copy(WindPreset dst, WindPreset src)
        {
            dst.flutter = src.flutter; dst.trunk = src.trunk; dst.branch = src.branch;
            dst.lean = src.lean; dst.global = src.global;
        }

        void Apply(WindPreset p)
        {
            Shader.SetGlobalFloat(ID_Global, Mathf.Clamp01(p.global));

            Vector4 dir = new Vector4(windDirection.x, windDirection.y, windDirection.z, 0f);
            for (int i = 0; i < targetMaterials.Count; i++)
            {
                var m = targetMaterials[i];
                if (m == null) continue;
                SetF(m, "_FlutterStrength", p.flutter);
                SetF(m, "_TrunkStrength", p.trunk);
                SetF(m, "_BranchStrength", p.branch);
                SetF(m, "_WindLean", p.lean);
                SetF(m, "_PhaseVariation", phaseVariation);   // однакова синхронність для всіх
                if (m.HasProperty("_WindDirection")) m.SetVector("_WindDirection", dir);
            }
        }

        static void SetF(Material m, string name, float v)
        {
            if (m.HasProperty(name)) m.SetFloat(name, v);
        }

        // Без _LEAN_WIND значення lean/global не діють — вмикаємо примусово.
        void SetupMaterials()
        {
            for (int i = 0; i < targetMaterials.Count; i++)
            {
                var m = targetMaterials[i];
                if (m == null) continue;
                m.EnableKeyword(KW_LEAN);
                if (m.HasProperty("_LeanIntoWind")) m.SetFloat("_LeanIntoWind", 1f);
            }
        }

        void EnsureMaterials()
        {
            if (targetMaterials == null || targetMaterials.Count == 0)
            {
                CollectSceneMaterials();
                if (targetMaterials.Count == 0)
                    Debug.LogWarning("[SimpleWind] Не знайдено матеріалів TreeWind3Channel. " +
                                     "Перетягни матеріал дерева (напр. 3Channel_1) у targetMaterials.", this);
            }
        }

        public void CollectSceneMaterials()
        {
            var set = new HashSet<Material>();
#if UNITY_2023_1_OR_NEWER
            var renderers = Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None);
#else
            var renderers = Object.FindObjectsOfType<Renderer>();
#endif
            foreach (var r in renderers)
                foreach (var m in r.sharedMaterials)
                    if (m != null && m.HasProperty("_LeanIntoWind"))
                        set.Add(m);
            targetMaterials = new List<Material>(set);
        }

        void OnEnable()
        {
            _lastTime = Time.realtimeSinceStartup;
            EnsureMaterials();
            SetupMaterials();
            Copy(_current, breeze);
#if UNITY_EDITOR
            if (!Application.isPlaying) EditorApplication.update += EditorStep;
#endif
        }

        void Update()
        {
            if (Application.isPlaying) Step(Time.deltaTime);
        }

        void OnValidate()
        {
            if (!Application.isPlaying && isActiveAndEnabled)
            {
                SetupMaterials();
                Apply(_current);
            }
        }

#if UNITY_EDITOR
        void OnDisable() { EditorApplication.update -= EditorStep; }

        void EditorStep()
        {
            if (Application.isPlaying) return;
            float now = Time.realtimeSinceStartup;
            float dt = Mathf.Min(now - _lastTime, 0.1f);
            _lastTime = now;
            Step(dt);
            SceneView.RepaintAll();
        }
#endif
    }

#if UNITY_EDITOR
    [CustomEditor(typeof(SimpleWind))]
    public class SimpleWindEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();
            var w = (SimpleWind)target;

            GUILayout.Space(8);
            if (w.targetMaterials == null || w.targetMaterials.Count == 0)
                EditorGUILayout.HelpBox("Список матеріалів порожній. Натисни 'Знайти матеріали'.", MessageType.Warning);

            if (GUILayout.Button("🔍 Знайти матеріали дерев на сцені", GUILayout.Height(26)))
            {
                Undo.RecordObject(w, "Collect Wind Materials");
                w.CollectSceneMaterials();
                EditorUtility.SetDirty(w);
            }

            GUILayout.Space(6);
            using (new GUILayout.HorizontalScope())
            {
                GUI.backgroundColor = new Color(0.6f, 0.85f, 0.6f);
                if (GUILayout.Button("🍃 Breeze", GUILayout.Height(38))) w.ToBreeze();
                GUI.backgroundColor = new Color(0.95f, 0.55f, 0.5f);
                if (GUILayout.Button("🌪 Storm", GUILayout.Height(38))) w.ToStorm();
                GUI.backgroundColor = Color.white;
            }

            if (w.IsPlaying)
            {
                EditorGUILayout.LabelField("Прогрес", $"{w.Progress * 100f:0}%");
                Repaint();
            }
        }
    }
#endif
}
