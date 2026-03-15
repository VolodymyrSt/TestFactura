using System;
using _Project.Code.Runtime.Configs.Enemy;
using _Project.Code.Runtime.GameLogic.HealthLogic;
using _Project.Code.Runtime.Infrastructure.CommonServices.StaticData;
using _Project.Code.Runtime.UI.HealthBar;
using UnityEngine;
using UnityEngine.AI;
using Zenject;

namespace _Project.Code.Runtime.GameLogic.Enemy
{
    public class EnemyHandler : MonoBehaviour, IDamageable
    {
        private readonly int _chaseHash = Animator.StringToHash("isChasing");
        private readonly int _idleHash = Animator.StringToHash("isIdling");
        
        [Header("Base")]
        [SerializeField] private NavMeshAgent _agent;
        [SerializeField] private Animator _animator;
        [SerializeField] private HealthBarView _healthBarView;
        [SerializeField] private ParticleSystem _bloodParticles;
        
        [Header("Target")]
        [SerializeField] private LayerMask _targetMask;
        
        private EnemyConfigSO _config;
        private float _detectionRadius;
        
        private EnemyState _currentState;
        private IEnemyTarget _target;
        private HealthSystem _healthSystem;
        
        [Inject]
        private void Construct(IStaticDataService staticDataService) => 
            _config = staticDataService.EnemyConfig;
        
        private void OnValidate()
        {
            _agent ??= GetComponent<NavMeshAgent>();
            _animator ??= GetComponentInChildren<Animator>();
        }

        private void Start()
        {
            _agent.speed = _config.Speed;
            _detectionRadius = _config.DetectionRadius;

            _healthSystem = new HealthSystem(_config.MaxHealth);
            _healthBarView.Bind(_healthSystem);
            
            SetState(EnemyState.Idle);
        }
        
        public void TakeDamage(float damage)
        {
            _healthSystem.Reduce(damage);
            
            _bloodParticles.Play();

            if (_healthSystem.Current <= 0)
                Die();
        }
        
        private void Update()
        {
            switch (_currentState) {
                case EnemyState.Idle: 
                    UpdateIdle();
                    break;
                case EnemyState.Chase:
                    UpdateChase();
                    break;
                case EnemyState.Attack:
                    ApplyDamage();
                    break;
            }
        }

        private void UpdateIdle()
        {
            if (TryFindTarget(out IEnemyTarget target))
            {
                _target = target;
                _agent.isStopped = false;
                SetState(EnemyState.Chase);
            }
        }
        
        private void UpdateChase()
        {
            if (_target != null && _target.IsAlive) 
                _agent.SetDestination(_target.Transform.position);
            else
            {
                _target = null;
                _agent.isStopped = true;
                SetState(EnemyState.Idle);
            }
        }

        private void ApplyDamage()
        {
            _target?.TakeDamage(_config.Damage);
            Die();
        }

        private void SetState(EnemyState state)
        {
            if (state == EnemyState.Chase)
                _animator.SetBool(_chaseHash, true);

            if (state == EnemyState.Idle)
                _animator.SetBool(_chaseHash, false);
            
            _currentState = state;
        }

        private void OnTriggerEnter(Collider other)
        {
            if (IsTargetLayer(other))
                SetState(EnemyState.Attack);
        }

        private bool TryFindTarget(out IEnemyTarget found)
        {
            found = null;
            
            Collider[] hits = Physics.OverlapSphere(transform.position, _detectionRadius, _targetMask);
            foreach (var hit in hits)
            {
                if (!hit.TryGetComponent(out IEnemyTarget target) || !target.IsAlive) continue;
                
                found = target;
                return true;
            }
            
            return false;
        }
        
        private bool IsTargetLayer(Collider other) => 
            (_targetMask.value & (1 << other.gameObject.layer)) != 0;

        private void Die()
        {
            _bloodParticles.transform.SetParent(null);
            _bloodParticles.Play();
            Destroy(_bloodParticles.gameObject, _bloodParticles.main.duration);
            Destroy(gameObject);
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = Color.green;
            Gizmos.DrawWireSphere(transform.position, Application.isPlaying ? _detectionRadius : 0f);
        }
    }
}
