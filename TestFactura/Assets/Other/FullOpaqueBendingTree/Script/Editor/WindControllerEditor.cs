using UnityEditor;
using UnityEngine;

namespace MyGame.Wind.EditorTools
{
    [CustomEditor(typeof(WindController))]
    public class WindControllerEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            var wind = (WindController)target;

            // Живий статус зверху
            DrawStatus(wind);
            EditorGUILayout.Space(6);

            DrawDefaultInspector();

            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("КЕРУВАННЯ ВІТРОМ", EditorStyles.boldLabel);

            // --- 3 ступені ---
            EditorGUILayout.LabelField("Плавний перехід до ступеня:", EditorStyles.miniBoldLabel);
            using (new EditorGUILayout.HorizontalScope())
            {
                if (ColorButton("🍃 Calm", new Color(0.6f, 0.85f, 0.6f))) wind.GoCalm();
                if (ColorButton("🌬 Medium", new Color(0.95f, 0.85f, 0.5f))) wind.GoMedium();
                if (ColorButton("🌪 Extreme", new Color(0.95f, 0.55f, 0.5f))) wind.GoExtreme();
            }

            EditorGUILayout.Space(4);

            // --- Наростання / затухання ---
            EditorGUILayout.LabelField("Секвенції:", EditorStyles.miniBoldLabel);
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("▲ Наростання\nCalm→Medium→Extreme", GUILayout.Height(38))) wind.PlayBuildup();
                if (GUILayout.Button("▼ Затухання\nдо штилю", GUILayout.Height(38))) wind.PlayCalmdown();
            }

            EditorGUILayout.Space(4);

            // --- Запланований порив ---
            EditorGUILayout.LabelField(
                $"Запланований порив: старт {wind.scheduledStartTime:0.#}с → кінець {wind.scheduledEndTime:0.#}с",
                EditorStyles.miniBoldLabel);
            if (GUILayout.Button("⏱ Запустити запланований порив", GUILayout.Height(30)))
                wind.ScheduleGust();

            EditorGUILayout.Space(4);

            // --- Стоп ---
            using (new EditorGUILayout.HorizontalScope())
            {
                if (ColorButton("■ Стоп / штиль", new Color(0.75f, 0.8f, 0.95f))) wind.KillWind();
                if (GUILayout.Button("✕ Скасувати секвенцію", GUILayout.Height(24))) wind.CancelSequence();
            }

            if (!Application.isPlaying)
                EditorGUILayout.HelpBox("Превʼю працює і в Edit-режимі. Для реальної гри натискай у Play.", MessageType.None);

            // Тримаємо інспектор живим, поки вітер рухається
            if (wind.SequenceRunning)
                Repaint();
        }

        void DrawStatus(WindController wind)
        {
            var s = wind.Current;
            var box = new GUIStyle(EditorStyles.helpBox) { fontSize = 11 };
            EditorGUILayout.BeginVertical(box);

            // Бар сили вітру
            Rect r = EditorGUILayout.GetControlRect(false, 16);
            EditorGUI.ProgressBar(r, wind.CurrentStrength01,
                $"Сила: {s.strength:0.00}   Розмір: {s.size:0.00}   Швидкість: {s.speed:0.00}");

            string seq = wind.SequenceRunning ? $"▶ секвенція t={wind.SequenceTime:0.0}с" : "● стабільно";
            EditorGUILayout.LabelField($"Напрям: ({s.direction.x:0.0}, {s.direction.y:0.0})    {seq}", EditorStyles.miniLabel);
            EditorGUILayout.EndVertical();
        }

        static bool ColorButton(string label, Color color)
        {
            Color prev = GUI.backgroundColor;
            GUI.backgroundColor = color;
            bool clicked = GUILayout.Button(label, GUILayout.Height(28));
            GUI.backgroundColor = prev;
            return clicked;
        }
    }
}
