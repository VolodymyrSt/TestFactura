using UnityEngine;

namespace _Project.Code.Runtime.Configs.Turret
{
    [CreateAssetMenu(fileName = "TurretConfig", menuName = "Configs/Turret/TurretConfig")]
    public class TurretConfigSO : ScriptableObject
    {
        [Header("Rotation Settings:")]
        [Range(25f, 100f)] public float RotationSpeed = 100f;
        [Range(1f, 20f)] public float Response = 10f;
        [Range(-30f, -90f)] public float MinAngle = -60f;
        [Range(30f, 90f)] public float MaxAngle = 60f;
    }
}