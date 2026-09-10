using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Sirenix.OdinInspector;

/// <summary>
/// Контролер вітру для шейдера Custom/TreeWind3Channel (URP).
/// Базові налаштування взяті з поточного "сильного" стану дерева.
/// </summary>
public class WindController : MonoBehaviour
{
    [TitleGroup("Materials")]
    [Tooltip("Основний матеріал, який використовує шейдер TreeWind3Channel.")]
    public Material targetMaterial;

    [Tooltip("Додаткові матеріали (якщо потрібно керувати кількома).")]
    public List<Material> additionalMaterials = new List<Material>();

    [Tooltip("Автоматично знайти всі матеріали з цим шейдером у сцені.")]
    public bool autoFindMaterials = true;

    // ------------------------------------------------------------
    //  ПАРАМЕТРИ ВІТРУ (ЗНАЧЕННЯ ЗА ЗАМОВЧУВАННЯМ = ЯК НА СКРІНШОТІ)
    // ------------------------------------------------------------
    [BoxGroup("Parameters")]
    [LabelText("Wind Speed (Швидкість)")]
    [Range(0f, 5f)]
    [OnValueChanged(nameof(OnWindSpeedChanged))]
    public float windSpeed = 1f;

    [BoxGroup("Parameters")]
    [LabelText("Gust Strength (Пориви)")]
    [Range(0f, 1f)]
    [OnValueChanged(nameof(OnGustStrengthChanged))]
    public float gustStrength = 0.5f;

    [BoxGroup("Parameters")]
    [LabelText("Gust Speed (Швидк. поривів)")]
    [Range(0f, 0.5f)]
    [OnValueChanged(nameof(OnGustSpeedChanged))]
    public float gustSpeed = 0.15f;

    [BoxGroup("Parameters")]
    [LabelText("Wind Lean (Нахил за вітром)")]
    [Range(0f, 1f)]
    [OnValueChanged(nameof(OnWindLeanChanged))]
    public float windLean = 0.5f; // Ваш Wind Lean Weight = 0.5

    [BoxGroup("Parameters")]
    [LabelText("Turbulence (Тремтіння)")]
    [Range(0f, 0.5f)]
    [OnValueChanged(nameof(OnTurbulenceChanged))]
    public float turbulence = 0.2f;

    [BoxGroup("Parameters")]
    [LabelText("Trunk Strength (Згин стовбура)")]
    [Range(0f, 10f)] // Використовую ваш діапазон (у вас стоїть 1)
    [OnValueChanged(nameof(OnTrunkStrengthChanged))]
    public float trunkStrength = 1f;

    [BoxGroup("Parameters")]
    [LabelText("Branch Strength (Гойдання гілок)")]
    [Range(0f, 1.5f)]
    [OnValueChanged(nameof(OnBranchStrengthChanged))]
    public float branchStrength = 0.45f; // Ваш Branch Swing = 0.45

    [BoxGroup("Parameters")]
    [LabelText("Flutter Strength (Флаттер листя)")]
    [Range(0f, 0.2f)]
    [OnValueChanged(nameof(OnFlutterStrengthChanged))]
    public float flutterStrength = 0.029f;

    [BoxGroup("Parameters")]
    [LabelText("Flutter Speed (Швидк. флаттера)")]
    [Range(0f, 20f)]
    [OnValueChanged(nameof(OnFlutterSpeedChanged))]
    public float flutterSpeed = 10.76f; // Ваше значення

    // ------------------------------------------------------------
    //  НАЛАШТУВАННЯ ПЕРЕХОДІВ
    // ------------------------------------------------------------
    [BoxGroup("Transition")]
    [LabelText("Default Transition Time (сек)")]
    [Range(0.1f, 10f)]
    public float defaultTransitionTime = 1.5f;

    // ------------------------------------------------------------
    //  СТАН LEAN (ключове слово шейдера)
    // ------------------------------------------------------------
    [BoxGroup("Lean Control")]
    [LabelText("Lean Enabled")]
    [OnValueChanged(nameof(OnLeanToggled))]
    public bool isLeanEnabled = true; // У вас Lean Into Wind = 1

    // ------------------------------------------------------------
    //  НАЛАШТУВАННЯ ПОРИВУ (BURST)
    // ------------------------------------------------------------
    [BoxGroup("Wind Burst")]
    [LabelText("Затримка перед поривом (сек)")]
    public float burstDelay = 5f;

    [BoxGroup("Wind Burst")]
    [LabelText("Тривалість пориву (сек)")]
    public float burstDuration = 10f;

    [BoxGroup("Wind Burst")]
    [LabelText("Цільова швидкість вітру")]
    [Range(1f, 10f)]
    public float burstStrength = 3f;

    [BoxGroup("Wind Burst")]
    [LabelText("Час переходу для пориву (сек)")]
    [Range(0.1f, 3f)]
    public float burstTransition = 1f;

    // ------------------------------------------------------------
    //  ДЕБАГ / ПОТОЧНИЙ СТАН (лише для читання)
    // ------------------------------------------------------------
    [BoxGroup("Debug / Current State")]
    [ShowInInspector, ReadOnly]
    [LabelText("Current Wind Speed")]
    private float DisplayWindSpeed => currentWindSpeed;

    [BoxGroup("Debug / Current State")]
    [ShowInInspector, ReadOnly]
    [LabelText("Current Lean State")]
    private string DisplayLeanState => isLeanEnabled ? "ON (Enabled)" : "OFF (Disabled)";

    // ------------------------------------------------------------
    //  ПРИВАТНІ ПОЛЯ ДЛЯ РОБОТИ
    // ------------------------------------------------------------
    private float currentWindSpeed;
    private float currentGustStrength;
    private float currentGustSpeed;
    private float currentWindLean;
    private float currentTurbulence;
    private float currentTrunkStrength;
    private float currentBranchStrength;
    private float currentFlutterStrength;
    private float currentFlutterSpeed;

    private float targetWindSpeed;
    private float targetGustStrength;
    private float targetGustSpeed;
    private float targetWindLean;
    private float targetTurbulence;
    private float targetTrunkStrength;
    private float targetBranchStrength;
    private float targetFlutterStrength;
    private float targetFlutterSpeed;

    private Coroutine lerpCoroutine;
    private Coroutine delayedActionCoroutine;
    private List<Material> allMaterials = new List<Material>();

    private const string GlobalWindStrength = "_GlobalWindStrength";

    // ------------------------------------------------------------
    //  ⭐ КНОПКИ ПРЕСЕТІВ (оновлена лінійка)
    // ------------------------------------------------------------
    [BoxGroup("Presets")]
    [Button(ButtonSizes.Large)]
    [GUIColor(0.3f, 0.9f, 1f)]
    public void Calm() => TriggerPreset("calm", defaultTransitionTime);

    [BoxGroup("Presets")]
    [Button(ButtonSizes.Large)]
    [GUIColor(0.3f, 1f, 0.3f)]
    public void LightBreeze() => TriggerPreset("light_breeze", defaultTransitionTime);

    [BoxGroup("Presets")]
    [Button(ButtonSizes.Large)]
    [GUIColor(1f, 1f, 0.3f)]
    public void Moderate() => TriggerPreset("moderate", defaultTransitionTime); // Ваш поточний стан

    [BoxGroup("Presets")]
    [Button(ButtonSizes.Large)]
    [GUIColor(1f, 0.6f, 0.2f)]
    public void Storm() => TriggerPreset("storm", defaultTransitionTime);

    [BoxGroup("Presets")]
    [Button(ButtonSizes.Large)]
    [GUIColor(1f, 0.2f, 0.2f)]
    public void Extreme() => TriggerPreset("extreme", defaultTransitionTime);

    // ------------------------------------------------------------
    //  КНОПКИ КЕРУВАННЯ LEAN
    // ------------------------------------------------------------
    [BoxGroup("Lean Control")]
    [Button(ButtonSizes.Medium)]
    [GUIColor(0.8f, 0.9f, 1f)]
    public void ToggleLean()
    {
        isLeanEnabled = !isLeanEnabled;
        SetLeanEnabled(isLeanEnabled);
    }

    // ------------------------------------------------------------
    //  КНОПКА ЗАПУСКУ ПОРИВУ
    // ------------------------------------------------------------
    [BoxGroup("Wind Burst")]
    [Button(ButtonSizes.Medium)]
    [GUIColor(1f, 0.7f, 0.3f)]
    public void ExecuteBurst()
    {
        StartWindBurst(burstDelay, burstDuration, burstStrength, burstTransition);
    }

    // ------------------------------------------------------------
    //  ІНІЦІАЛІЗАЦІЯ ТА ЗБІР МАТЕРІАЛІВ
    // ------------------------------------------------------------
    private void Awake()
    {
        allMaterials.Clear();

        if (targetMaterial != null)
            allMaterials.Add(targetMaterial);

        if (additionalMaterials != null)
            allMaterials.AddRange(additionalMaterials);

        if (autoFindMaterials)
        {
            var renderers = FindObjectsOfType<Renderer>();
            foreach (var renderer in renderers)
            {
                foreach (var mat in renderer.sharedMaterials)
                {
                    if (mat != null && mat.shader != null && mat.shader.name == "Custom/TreeWind3Channel")
                    {
                        if (!allMaterials.Contains(mat))
                            allMaterials.Add(mat);
                    }
                }
            }
        }

        if (allMaterials.Count == 0)
        {
            Debug.LogWarning("WindController: No materials found with shader 'Custom/TreeWind3Channel'.");
        }

        // Зчитуємо початкові значення з першого матеріалу (або беремо з інспектора)
        if (allMaterials.Count > 0)
        {
            var mat = allMaterials[0];
            windSpeed = mat.GetFloat("_WindSpeed");
            gustStrength = mat.GetFloat("_GustStrength");
            gustSpeed = mat.GetFloat("_GustSpeed");
            windLean = mat.GetFloat("_WindLean");
            turbulence = mat.GetFloat("_Turbulence");
            trunkStrength = mat.GetFloat("_TrunkStrength");
            branchStrength = mat.GetFloat("_BranchStrength");
            flutterStrength = mat.GetFloat("_FlutterStrength");
            flutterSpeed = mat.GetFloat("_FlutterSpeed");
            isLeanEnabled = mat.IsKeywordEnabled("_LEAN_WIND");
        }

        // Синхронізуємо цільові значення з поточними
        targetWindSpeed = windSpeed;
        targetGustStrength = gustStrength;
        targetGustSpeed = gustSpeed;
        targetWindLean = windLean;
        targetTurbulence = turbulence;
        targetTrunkStrength = trunkStrength;
        targetBranchStrength = branchStrength;
        targetFlutterStrength = flutterStrength;
        targetFlutterSpeed = flutterSpeed;

        currentWindSpeed = targetWindSpeed;
        currentGustStrength = targetGustStrength;
        currentGustSpeed = targetGustSpeed;
        currentWindLean = targetWindLean;
        currentTurbulence = targetTurbulence;
        currentTrunkStrength = targetTrunkStrength;
        currentBranchStrength = targetBranchStrength;
        currentFlutterStrength = targetFlutterStrength;
        currentFlutterSpeed = targetFlutterSpeed;

        ApplySettingsImmediate();
    }

    // ------------------------------------------------------------
    //  ОБРОБНИКИ ЗМІНИ ПАРАМЕТРІВ (OnValueChanged)
    // ------------------------------------------------------------
    private void OnWindSpeedChanged() => SetWindSpeed(windSpeed, defaultTransitionTime);
    private void OnGustStrengthChanged() => SetGustStrength(gustStrength, defaultTransitionTime);
    private void OnGustSpeedChanged() => SetGustSpeed(gustSpeed, defaultTransitionTime);
    private void OnWindLeanChanged() => SetWindLean(windLean, defaultTransitionTime);
    private void OnTurbulenceChanged() => SetTurbulence(turbulence, defaultTransitionTime);
    private void OnTrunkStrengthChanged() => SetTrunkStrength(trunkStrength, defaultTransitionTime);
    private void OnBranchStrengthChanged() => SetBranchStrength(branchStrength, defaultTransitionTime);
    private void OnFlutterStrengthChanged() => SetFlutterStrength(flutterStrength, defaultTransitionTime);
    private void OnFlutterSpeedChanged() => SetFlutterSpeed(flutterSpeed, defaultTransitionTime);
    private void OnLeanToggled() => SetLeanEnabled(isLeanEnabled);

    // ------------------------------------------------------------
    //  ПУБЛІЧНІ МЕТОДИ КЕРУВАННЯ
    // ------------------------------------------------------------
    public void SetWindSpeed(float value, float duration = 0f) => StartLerp(() => targetWindSpeed = Mathf.Max(0, value), duration);
    public void SetGustStrength(float value, float duration = 0f) => StartLerp(() => targetGustStrength = Mathf.Clamp01(value), duration);
    public void SetGustSpeed(float value, float duration = 0f) => StartLerp(() => targetGustSpeed = Mathf.Max(0, value), duration);
    public void SetWindLean(float value, float duration = 0f) => StartLerp(() => targetWindLean = Mathf.Clamp01(value), duration);
    public void SetTurbulence(float value, float duration = 0f) => StartLerp(() => targetTurbulence = Mathf.Clamp01(value), duration);
    public void SetTrunkStrength(float value, float duration = 0f) => StartLerp(() => targetTrunkStrength = Mathf.Max(0, value), duration);
    public void SetBranchStrength(float value, float duration = 0f) => StartLerp(() => targetBranchStrength = Mathf.Max(0, value), duration);
    public void SetFlutterStrength(float value, float duration = 0f) => StartLerp(() => targetFlutterStrength = Mathf.Max(0, value), duration);
    public void SetFlutterSpeed(float value, float duration = 0f) => StartLerp(() => targetFlutterSpeed = Mathf.Max(0, value), duration);

    public void SetLeanEnabled(bool enabled)
    {
        isLeanEnabled = enabled;
        ApplyKeywordToMaterials();
    }

    // ------------------------------------------------------------
    //  ⭐ ОНОВЛЕНИЙ МЕТОД ПРЕСЕТІВ
    // ------------------------------------------------------------
    public void TriggerPreset(string presetName, float transitionTime)
    {
        switch (presetName.ToLower())
        {
            case "calm": // Штиль (дерево майже не рухається)
                SetWindSpeed(0.1f, transitionTime);
                SetGustStrength(0.05f, transitionTime);
                SetGustSpeed(0.05f, transitionTime);
                SetWindLean(0f, transitionTime);
                SetTurbulence(0.02f, transitionTime);
                SetTrunkStrength(0.1f, transitionTime);
                SetBranchStrength(0.05f, transitionTime);
                SetFlutterStrength(0.005f, transitionTime);
                SetFlutterSpeed(5f, transitionTime);
                SetLeanEnabled(false);
                break;

            case "light_breeze": // Легкий бриз (половина від ваших поточних)
                SetWindSpeed(0.5f, transitionTime);
                SetGustStrength(0.25f, transitionTime);
                SetGustSpeed(0.1f, transitionTime);
                SetWindLean(0.2f, transitionTime);
                SetTurbulence(0.1f, transitionTime);
                SetTrunkStrength(0.3f, transitionTime);
                SetBranchStrength(0.2f, transitionTime);
                SetFlutterStrength(0.015f, transitionTime);
                SetFlutterSpeed(8f, transitionTime);
                SetLeanEnabled(true);
                break;

            case "moderate": // ПОМІРНИЙ (ВАШІ ПОТОЧНІ "СИЛЬНІ" НАЛАШТУВАННЯ)
                SetWindSpeed(1f, transitionTime);
                SetGustStrength(0.5f, transitionTime);
                SetGustSpeed(0.15f, transitionTime);
                SetWindLean(0.5f, transitionTime);
                SetTurbulence(0.2f, transitionTime);
                SetTrunkStrength(0.7f, transitionTime);
                SetBranchStrength(0.45f, transitionTime);
                SetFlutterStrength(0.029f, transitionTime);
                SetFlutterSpeed(10.76f, transitionTime);
                SetLeanEnabled(true);
                break;

            case "storm": // Шторм (посилюємо ваші налаштування в 1.5-2 рази)
                SetWindSpeed(1.5f, transitionTime);
                SetGustStrength(0.9f, transitionTime);
                SetGustSpeed(0.3f, transitionTime);
                SetWindLean(0.8f, transitionTime);
                SetTurbulence(0.35f, transitionTime);
                SetTrunkStrength(0.9f, transitionTime);
                SetBranchStrength(0.8f, transitionTime);
                SetFlutterStrength(0.06f, transitionTime);
                SetFlutterSpeed(15f, transitionTime);
                SetLeanEnabled(true);
                break;

            case "extreme": // Екстрим (майже максимальні значення)
                SetWindSpeed(2.5f, transitionTime);
                SetGustStrength(1f, transitionTime);
                SetGustSpeed(0.5f, transitionTime);
                SetWindLean(1f, transitionTime);
                SetTurbulence(0.5f, transitionTime);
                SetTrunkStrength(1f, transitionTime);
                SetBranchStrength(1.2f, transitionTime);
                SetFlutterStrength(0.12f, transitionTime);
                SetFlutterSpeed(20f, transitionTime);
                SetLeanEnabled(true);
                break;

            default:
                Debug.LogWarning($"WindController: Unknown preset '{presetName}'.");
                break;
        }
    }

    public void StartWindBurst(float delay, float duration, float targetStrength, float transitionTime)
    {
        if (delayedActionCoroutine != null)
            StopCoroutine(delayedActionCoroutine);
        delayedActionCoroutine = StartCoroutine(WindBurstRoutine(delay, duration, targetStrength, transitionTime));
    }

    // ------------------------------------------------------------
    //  ВНУТРІШНІ КОРУТИНИ
    // ------------------------------------------------------------
    private void StartLerp(System.Action setTargetAction, float duration)
    {
        setTargetAction?.Invoke();
        if (lerpCoroutine != null)
            StopCoroutine(lerpCoroutine);
        lerpCoroutine = StartCoroutine(LerpRoutine(duration));
    }

    private IEnumerator LerpRoutine(float duration)
    {
        if (duration <= 0f)
        {
            ApplySettingsImmediate();
            lerpCoroutine = null;
            yield break;
        }

        float startWindSpeed = currentWindSpeed;
        float startGustStrength = currentGustStrength;
        float startGustSpeed = currentGustSpeed;
        float startWindLean = currentWindLean;
        float startTurbulence = currentTurbulence;
        float startTrunkStrength = currentTrunkStrength;
        float startBranchStrength = currentBranchStrength;
        float startFlutterStrength = currentFlutterStrength;
        float startFlutterSpeed = currentFlutterSpeed;

        float elapsed = 0f;
        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = Mathf.Clamp01(elapsed / duration);

            currentWindSpeed = Mathf.Lerp(startWindSpeed, targetWindSpeed, t);
            currentGustStrength = Mathf.Lerp(startGustStrength, targetGustStrength, t);
            currentGustSpeed = Mathf.Lerp(startGustSpeed, targetGustSpeed, t);
            currentWindLean = Mathf.Lerp(startWindLean, targetWindLean, t);
            currentTurbulence = Mathf.Lerp(startTurbulence, targetTurbulence, t);
            currentTrunkStrength = Mathf.Lerp(startTrunkStrength, targetTrunkStrength, t);
            currentBranchStrength = Mathf.Lerp(startBranchStrength, targetBranchStrength, t);
            currentFlutterStrength = Mathf.Lerp(startFlutterStrength, targetFlutterStrength, t);
            currentFlutterSpeed = Mathf.Lerp(startFlutterSpeed, targetFlutterSpeed, t);

            ApplySettings();
            yield return null;
        }

        currentWindSpeed = targetWindSpeed;
        currentGustStrength = targetGustStrength;
        currentGustSpeed = targetGustSpeed;
        currentWindLean = targetWindLean;
        currentTurbulence = targetTurbulence;
        currentTrunkStrength = targetTrunkStrength;
        currentBranchStrength = targetBranchStrength;
        currentFlutterStrength = targetFlutterStrength;
        currentFlutterSpeed = targetFlutterSpeed;
        ApplySettings();

        lerpCoroutine = null;
    }

    private IEnumerator WindBurstRoutine(float delay, float duration, float targetStrength, float transitionTime)
    {
        float originalSpeed = currentWindSpeed;
        float originalGust = currentGustStrength;
        float originalLean = currentWindLean;

        yield return new WaitForSeconds(delay);

        SetWindSpeed(targetStrength, transitionTime);
        SetGustStrength(Mathf.Min(currentGustStrength * 1.5f, 1f), transitionTime);
        SetWindLean(0.8f, transitionTime);

        yield return new WaitForSeconds(duration);

        SetWindSpeed(originalSpeed, transitionTime);
        SetGustStrength(originalGust, transitionTime);
        SetWindLean(originalLean, transitionTime);

        delayedActionCoroutine = null;
    }

    // ------------------------------------------------------------
    //  ЗАСТОСУВАННЯ
    // ------------------------------------------------------------
    private void ApplySettingsImmediate()
    {
        currentWindSpeed = targetWindSpeed;
        currentGustStrength = targetGustStrength;
        currentGustSpeed = targetGustSpeed;
        currentWindLean = targetWindLean;
        currentTurbulence = targetTurbulence;
        currentTrunkStrength = targetTrunkStrength;
        currentBranchStrength = targetBranchStrength;
        currentFlutterStrength = targetFlutterStrength;
        currentFlutterSpeed = targetFlutterSpeed;

        // Оновлюємо поля інспектора
        windSpeed = currentWindSpeed;
        gustStrength = currentGustStrength;
        gustSpeed = currentGustSpeed;
        windLean = currentWindLean;
        turbulence = currentTurbulence;
        trunkStrength = currentTrunkStrength;
        branchStrength = currentBranchStrength;
        flutterStrength = currentFlutterStrength;
        flutterSpeed = currentFlutterSpeed;

        ApplySettings();
        ApplyKeywordToMaterials();
    }

    private void ApplySettings()
    {
        foreach (var mat in allMaterials)
        {
            if (mat == null) continue;
            mat.SetFloat("_WindSpeed", currentWindSpeed);
            mat.SetFloat("_GustStrength", currentGustStrength);
            mat.SetFloat("_GustSpeed", currentGustSpeed);
            mat.SetFloat("_WindLean", currentWindLean);
            mat.SetFloat("_Turbulence", currentTurbulence);
            mat.SetFloat("_TrunkStrength", currentTrunkStrength);
            mat.SetFloat("_BranchStrength", currentBranchStrength);
            mat.SetFloat("_FlutterStrength", currentFlutterStrength);
            mat.SetFloat("_FlutterSpeed", currentFlutterSpeed);
        }

        // Глобальна сила вітру (для зовнішніх ефектів)
        Shader.SetGlobalFloat(GlobalWindStrength, currentWindSpeed * 0.5f);
    }

    private void ApplyKeywordToMaterials()
    {
        foreach (var mat in allMaterials)
        {
            if (mat == null) continue;
            if (isLeanEnabled)
                mat.EnableKeyword("_LEAN_WIND");
            else
                mat.DisableKeyword("_LEAN_WIND");
        }
    }

    // ------------------------------------------------------------
    //  СКИДАННЯ ДО ПОТОЧНОГО "MODERATE" (опціонально)
    // ------------------------------------------------------------
    [Button(ButtonSizes.Small)]
    [GUIColor(0.5f, 0.5f, 0.5f)]
    [FoldoutGroup("Debug")]
    private void ResetToModerate()
    {
        TriggerPreset("moderate", defaultTransitionTime);
    }
}