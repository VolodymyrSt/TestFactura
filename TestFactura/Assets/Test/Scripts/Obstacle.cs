using UnityEngine;

namespace Test.Scripts
{
    public class Obstacle : MonoBehaviour, IHittable
    {
        [SerializeField] private ObstacleConfig _config;
        
        public ObstacleConfig Config => _config;
    }
}