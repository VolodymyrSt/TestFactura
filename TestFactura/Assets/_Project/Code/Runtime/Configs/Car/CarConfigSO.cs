using UnityEngine;

namespace _Project.Code.Runtime.Configs.Car
{
    [CreateAssetMenu(fileName = "CarConfig", menuName = "Configs/Car/CarConfig")]
    public class CarConfigSO : ScriptableObject
    {
        [Range(1f, 25f)] public float Speed;
        [Range(1f, 20f)] public float Health = 10f;
    }
}