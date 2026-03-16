using UnityEngine;

namespace _Project.Code.Runtime.Configs.Car
{
    [CreateAssetMenu(fileName = "CarConfig", menuName = "Configs/Car/CarConfig")]
    public class CarConfigSO : ScriptableObject
    {
        [Header("Stats:")]
        [Range(1f, 25f)] public float Speed;
        [Range(1f, 5f)] public float StoppingDistance = 3f;
        [Range(1f, 50f)] public float MaxHealth = 10f;
    }
}