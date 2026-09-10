using UnityEngine;

namespace Test.Scripts
{
    [CreateAssetMenu(fileName = "ObstacleConfig", menuName = "Game/ObstacleConfig")]
    public class ObstacleConfig : ScriptableObject
    {
        [Range(0f, 1f)]
        public float centerHitThreshold = 0.6f;
    }
}