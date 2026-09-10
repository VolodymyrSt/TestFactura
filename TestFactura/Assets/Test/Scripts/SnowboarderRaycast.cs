using System;
using UnityEngine;

namespace Test.Scripts
{
   public class SnowboarderRaycast : MonoBehaviour
    {
        [Header("Base")]
        [SerializeField] private float _sphereRadius = 0.3f;
        [SerializeField] private LayerMask _obstacleLayer;
        [SerializeField] private Vector3 _size;
        [SerializeField] private Vector3 _offset;
        
        [Header("Settings")]
        [SerializeField] private bool _withRaycast = true;
        [SerializeField] private int _frameRate = 60;

        private Vector3 _previousPosition;
        private float _hitCooldown;

        private void Start()
        {
            //Application.targetFrameRate = 10;
            if (!_withRaycast) return;
            _previousPosition = transform.position;
        }

        private void Update() => 
            Application.targetFrameRate = _frameRate;

        private void OnCollisionEnter(Collision collision)
        {
            if (_withRaycast) return;
            
            if (!collision.gameObject.TryGetComponent(out IHittable hittable)) return;

            Vector3 contactNormal = collision.contacts[0].normal;
            
            Vector3 incomingDir = transform.forward;
            float dot = Vector3.Dot(incomingDir, -contactNormal);

            if (dot >= hittable.Config.centerHitThreshold)
            {
                Debug.Log("Death");
            }
            else
            {
                Debug.Log("Slowdown");
            }
        }

        private void FixedUpdate()
        {
            if (!_withRaycast) return;
            
            if (_hitCooldown > 0f)
            {
                _hitCooldown -= Time.fixedDeltaTime;
                _previousPosition = transform.position;
                return;
            }

            Vector3 moveDir = (transform.position - _previousPosition);
            float moveDistance = moveDir.magnitude;

            if (Physics.BoxCast(_previousPosition + _offset, _size / 2, moveDir.normalized,
                    out RaycastHit hit, Quaternion.LookRotation(transform.forward), moveDistance + 0.1f, _obstacleLayer))
            {
                if (hit.collider.TryGetComponent(out IHittable hittable))
                {
                    float dot = Vector3.Dot(moveDir.normalized, -hit.normal);
                    
                    if (dot >= hittable.Config.centerHitThreshold)
                    {
                        Debug.Log("Death");
                    }
                    else
                    {
                        Debug.Log("Slowdown");
                    }

                    _hitCooldown = 0.5f;
                }
            }
            
            _previousPosition = transform.position;
        }

        private void OnDrawGizmos()
        {
            Gizmos.color = Color.cyan;
    
            // зберігаємо матрицю і застосовуємо rotation персонажа
            Matrix4x4 oldMatrix = Gizmos.matrix;
            Gizmos.matrix = Matrix4x4.TRS(
                transform.position + _offset,
                Quaternion.LookRotation(transform.forward),
                Vector3.one);
    
            Gizmos.DrawWireCube(Vector3.zero, _size);
    
            Gizmos.matrix = oldMatrix; // відновлюємо
    
            Gizmos.DrawRay(transform.position, transform.forward * 1.5f);
        }
    }
}