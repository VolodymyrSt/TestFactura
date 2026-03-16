using DG.Tweening;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Barrier
{
    public class BarriersHandler : MonoBehaviour
    {
        [Header("Sticks:")]
        [SerializeField] private Transform _leftBarrierStick;
        [SerializeField] private Transform _rightBarrierStick;
        
        [Header("Rotation:")]
        [SerializeField] private Vector3 _targetRotation;
        [SerializeField] private float _duration;
        [SerializeField] private Ease _ease;

        public void Open()
        {
            _leftBarrierStick.DOLocalRotate(_targetRotation, _duration)
                .SetEase(_ease)
                .Play();
            
            _rightBarrierStick.DOLocalRotate(_targetRotation, _duration)
                .SetEase(_ease)
                .Play();
        }
    }
}