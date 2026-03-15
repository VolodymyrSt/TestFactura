using System;
using _Project.Code.Runtime.Configs.Car;
using _Project.Code.Runtime.GameLogic.Enemy;
using _Project.Code.Runtime.GameLogic.HealthLogic;
using _Project.Code.Runtime.UI.HealthBar;
using DG.Tweening;
using UnityEngine;
using UnityEngine.AI;

namespace _Project.Code.Runtime.GameLogic.Car
{
    public class CarHandler : MonoBehaviour, ICar, IEnemyTarget
    {
        public event Action OnDestroyed;
        public event Action OnReachedDestination;
        
        [Header("Base")]
        [SerializeField] private NavMeshAgent _agent;
        [SerializeField] private HealthBarView _healthBarView;
        
        [Header("Turret Installation")]
        [SerializeField] private Transform _turretInstallPoint;
        
        public Transform CameraTarget => transform;
        public bool IsAlive => _healthSystem != null && _healthSystem.Current > 0;
        public Transform Transform => transform;
        public Transform TurretInstallPoint => _turretInstallPoint;
        
        private HealthSystem _healthSystem;
        
        private void OnValidate()
        {
            _agent ??= GetComponent<NavMeshAgent>();
            _healthBarView ??= GetComponentInChildren<HealthBarView>();
        }

        public void SetUp(Vector3 destinationPosition, CarConfigSO config)
        {
            _healthSystem = new HealthSystem(config.MaxHealth);
            _healthBarView.Bind(_healthSystem);

            _agent.SetDestination(destinationPosition);
            _agent.speed = config.Speed;
            _agent.stoppingDistance = config.StoppingDistance;
            _agent.isStopped = true;
        }

        private void Update()
        {
            if (_agent.isStopped || _agent.pathPending) return;
            
            if (IsReachedDestination())
            {
                _agent.isStopped = true;
                OnReachedDestination?.Invoke();
            }
        }

        public void StartMoving() =>
            _agent.isStopped = false;

        public void TakeDamage(float damage)
        {
            _healthSystem.Reduce(damage);
            PlayHitShake();
            
            if (_healthSystem.Current <= 0)
            {
                _agent.isStopped = true;
                OnDestroyed?.Invoke();
                Debug.Log("Game Over");
            }
        }
        
        private void PlayHitShake()
        {
            transform.DOKill();
            transform.DOShakePosition(
                    duration: 0.1f,
                    strength: new Vector3(0.002f, 0.0005f, 0.002f),
                    vibrato: 2,
                    randomness: 45,
                    fadeOut: true)
                .SetEase(Ease.OutQuad)
                .Play()
                .SetLink(gameObject);
        }
        
        private bool IsReachedDestination() => 
            _agent.hasPath && _agent.remainingDistance <= _agent.stoppingDistance;
    }
}
