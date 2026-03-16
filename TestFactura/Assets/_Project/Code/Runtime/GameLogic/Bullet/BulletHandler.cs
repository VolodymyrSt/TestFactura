using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.GameLogic.Enemy;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Bullet
{
    public class BulletHandler : MonoBehaviour, IBullet
    {
        [Header("Base:")]
        [SerializeField] private LayerMask _targetMask;
        [SerializeField] private TrailRenderer _trail;
        [SerializeField] private Rigidbody _rigidbody;
        
        private IBulletPool _pool;
        
        private Vector3 _direction;
        private float _lifeTime;
        private bool _isFired;
        private float _liveTimer;
        private float _damage;
        
        private void OnValidate() =>
            _rigidbody ??= GetComponent<Rigidbody>();
        
        public void Init(IBulletPool bulletPool) => 
            _pool = bulletPool;

        public void Warp(Transform warpPoint)
        {
            transform.position = warpPoint.position;
            transform.rotation = warpPoint.rotation;
        }
        
        public void Reset()
        {
            _rigidbody.linearVelocity = Vector3.zero;
            _rigidbody.angularVelocity = Vector3.zero;
        }

        public void Fire(Vector3 direction, float force, float lifeTime, float damage)
        {
            _direction = direction;
            _lifeTime = lifeTime;
            _damage = damage;
            _liveTimer = 0f;
            
            _rigidbody.AddForce(direction.normalized * force, ForceMode.Impulse);
            transform.rotation = Quaternion.LookRotation(_direction);
            
            _trail.enabled = true;
            _trail.Clear();
            
            _isFired = true;
        }
        
        private void Update()
        {
            if (!_isFired) return;
            
            _liveTimer += Time.deltaTime;
            if (_liveTimer >= _lifeTime)
                ReturnToPool();
        }
        
        public void SetActive(bool active) =>
            gameObject.SetActive(active);
        
        private void OnTriggerEnter(Collider other)
        {
            if (!_isFired) return;
            
            if (IsTargetLayer(other) && other.TryGetComponent(out IDamageable damageable))
                damageable.TakeDamage(_damage);

            ReturnToPool();
        }
        
        private void ReturnToPool()
        {
            _isFired = false;
            _trail.enabled = false;
            _trail.Clear();
            _pool.Release(this);
        }
        
        private bool IsTargetLayer(Collider other) => 
            (_targetMask.value & (1 << other.gameObject.layer)) != 0;
    }
}