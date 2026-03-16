using UnityEngine;

namespace _Project.Code.Runtime.Configs.Enemy
{
    [CreateAssetMenu(fileName = "EnemyConfig", menuName = "Configs/Enemy/EnemyConfig")]
    public class EnemyConfigSO : ScriptableObject
    {
        [Range(1f, 12f)] public float Speed = 3f;
        [Range(1f, 20f)] public float Damage = 10f;
        [Range(1f, 20f)] public float MaxHealth = 10f;
        
        [Header("Detection:")]
        [Range(1f, 20f)] public float DetectionRadius = 10f;
    }
}