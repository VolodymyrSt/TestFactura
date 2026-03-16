using System;
using _Project.Code.Runtime.Configs.Turret;
using _Project.Code.Runtime.GameLogic.Bullet;
using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.GameLogic.Turret
{
    public class TurretHandler : MonoBehaviour, ITurret
    {
        [Header("Base:")]
        [SerializeField] private Transform _visual;
        [SerializeField] private Transform _bulletWarpPoint;
        
        [Header("Laser:")]
        [SerializeField] private LineRenderer _laser;
        
        private IInputService _inputService;
        private IBulletPool _bulletPool;
        private TurretConfigSO _config;
        
        private float _currentYAngle;
        private float _targetYAngle;

        private float _fireCooldown;
        private bool _isActive;
        
        [Inject]
        private void Construct(IInputService inputService, IBulletPool bulletPool)
        {
            _inputService = inputService;
            _bulletPool = bulletPool;
        }

        public void Init(TurretConfigSO config)
        {
            _config = config;
            
            _bulletPool.Preload(initialCount: 7);
            
            SetUpLaser();
            ResetFireCooldown();
            Deactivate();
        }
        
        public void Activate() => _isActive = true;
        public void Deactivate() => _isActive = false;

        public void InstallOn(Transform installPoint)
        {
            transform.SetParent(installPoint, false);
            transform.localPosition = Vector3.zero;
            
            _currentYAngle = _visual.localEulerAngles.y;
            _targetYAngle = _currentYAngle;
        }

        private void Update()
        {
            if (!_isActive) return;
            
            UpdateRotation();

            if (IsReadyToFire())
            {
                PerformFire();
                ResetFireCooldown();
            }
            
            UpdateFireCooldown();
        }

        private void PerformFire()
        {
            IBullet bullet = _bulletPool.Get();
            bullet.Warp(_bulletWarpPoint);
            bullet.Fire(_bulletWarpPoint.forward, _config.BulletForce, _config.BulletLifeTime, _config.Damage);
        }
        
        private void UpdateRotation()
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
            
            _visual.localRotation = Quaternion.Euler(0f, _currentYAngle, 0f);
        }
        
        private void SetUpLaser()
        {
            _laser.SetPosition(0, Vector3.zero);
            _laser.SetPosition(1, _bulletWarpPoint.forward * _config.LaserLength);
        }
        
        private void UpdateFireCooldown() =>
            _fireCooldown -= Time.deltaTime;
        
        private bool IsReadyToFire() => 
            _fireCooldown <= 0;
        
        private void ResetFireCooldown() =>
            _fireCooldown = _config.FireCooldown;
    }
}
