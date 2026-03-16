using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.DistаnceIndicator
{
    public interface IDistanceIndicator
    {
        void Setup(float start, float end, Transform target);
        void Tick();
    }
}