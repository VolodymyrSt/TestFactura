using UnityEngine;

namespace _Project.Code.Runtime.Configs.Car
{
    [CreateAssetMenu(fileName = "CarConfig", menuName = "Configs/Car/CarConfig")]
    public class CarConfigSO : ScriptableObject
    {
        [Range(0, 25)] public float Speed;
    }
}