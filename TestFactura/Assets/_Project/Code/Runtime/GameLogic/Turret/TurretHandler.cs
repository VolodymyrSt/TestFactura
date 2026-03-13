using System;
using _Project.Code.Runtime.Configs.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.GameLogic.Turret
{
    public class TurretHandler : MonoBehaviour, ITurret
    {
        private IInputService _inputService;
        private TurretConfigSO _config;
        
        private float _currentYAngle;
        private float _targetYAngle;
        
        [Inject]
        private void Construct(IInputService inputService) => 
            _inputService = inputService;

        public void Init(TurretConfigSO config) => 
            _config = config;

        public void InstallOn(Transform installPoint)
        {
            transform.SetParent(installPoint, false);
            transform.localPosition = Vector3.zero;
            
            _currentYAngle = transform.localEulerAngles.y;
            _targetYAngle = _currentYAngle;
        }

        private void Update()
        {
            float delta = _inputService.GetSwipeDelta().x;
            RotateByDelta(delta);
        }

        private void RotateByDelta(float delta)
        {
            _targetYAngle += delta * _config.RotationSpeed * Time.deltaTime;
            _targetYAngle = Mathf.Clamp(_targetYAngle, _config.MinAngle, _config.MaxAngle);

            _currentYAngle = Mathf.LerpAngle(_currentYAngle, _targetYAngle, 
                _config.Response * Time.deltaTime);
            
            transform.rotation = Quaternion.Euler(0f, _currentYAngle, 0f);
        }
    }
}