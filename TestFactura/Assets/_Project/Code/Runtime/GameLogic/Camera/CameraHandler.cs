using Unity.Cinemachine;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Camera
{
    public class CameraHandler : MonoBehaviour, ICamera
    {
        [SerializeField] private CinemachineCamera _cinemachineCamera;
        
        private void OnValidate() => 
            _cinemachineCamera ??= GetComponentInChildren<CinemachineCamera>();

        public void SetTarget(Transform target)
        {
            _cinemachineCamera.Target = new CameraTarget {
                TrackingTarget = target,
                LookAtTarget = target,
            };
        }
    }
}