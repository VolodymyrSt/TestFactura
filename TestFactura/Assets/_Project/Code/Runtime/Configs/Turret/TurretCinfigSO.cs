using UnityEngine;

namespace _Project.Code.Runtime.Configs.Turret
{
    [CreateAssetMenu(fileName = "TurretConfig", menuName = "Configs/Turret/TurretConfig")]
    public class TurretConfigSO : ScriptableObject
    {
        [Header("Rotation Settings:")]
        [Range(1f, 100f)] public float RotationSpeed = 100f;
        [Range(1f, 20f)] public float Response = 10f;
        [Range(-30f, -90f)] public float MinAngle = -60f;
        [Range(30f, 90f)] public float MaxAngle = 60f;
        
        [Header("Impact Settings:")]
        [Range(5f, 10f)] public float Damage = 10f;
        [Range(0.2f, 5f)] public float FireCooldown = 1f;
        [Range(0.5f, 50f)] public float BulletForce = 30f;
        [Range(0.5f, 5f)] public float BulletLifeTime = 3f;
        
        [Header("Visual Settings:")]
        [Range(5f, 15f)] public float LaserLength = 10f;
    }
}