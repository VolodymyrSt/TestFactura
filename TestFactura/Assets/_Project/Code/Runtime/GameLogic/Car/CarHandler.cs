using System;
using _Project.Code.Runtime.GameLogic.Enemy;
using _Project.Code.Runtime.GameLogic.HealthLogic;
using _Project.Code.Runtime.UI.HealthBar;
using UnityEngine;
using UnityEngine.AI;

namespace _Project.Code.Runtime.GameLogic.Car
{
    public class CarHandler : MonoBehaviour, ICar, IEnemyTarget
    {
        public event Action OnDestroyed;
        public event Action OnReachedEnd;
        
        [Header("Base")]
        [SerializeField] private NavMeshAgent _agent;
        [SerializeField] private HealthBarView _healthBarView;
        
        [Header("Turret Installation")]
        [SerializeField] private Transform _turretInstallPoint;
        
        public Transform CameraTarget => transform;
        public bool IsAlive => _healthSystem.Current > 0;
        public Transform Transform => transform;
        public Transform TurretInstallPoint => _turretInstallPoint;
        
        private HealthSystem _healthSystem;
        
        private void OnValidate()
        {
            _agent ??= GetComponent<NavMeshAgent>();
            _healthBarView ??= GetComponentInChildren<HealthBarView>();
        }

        public void SetUp(Vector3 warpPoint, Vector3 destinationPoint,
            float moveSpeed, float maxHealth)
        {
            _healthSystem = new HealthSystem(maxHealth);
            _healthBarView.Bind(_healthSystem);
            
            _agent.Warp(warpPoint);
            _agent.SetDestination(destinationPoint);
            _agent.speed = moveSpeed;
            _agent.isStopped = true;
        }

        public void StartMoving() => 
            _agent.isStopped = false;

        public void TakeDamage(float damage)
        {
            _healthSystem.Reduce(damage);

            if (_healthSystem.Current <= 0)
            {
                _agent.isStopped = true;
                OnDestroyed?.Invoke();
                Debug.Log("Game Over");
            }
        }
    }
}