using System.Collections;
using UnityEngine;

namespace Test.Scripts
{
    public class TreeBend : MonoBehaviour
    {
        [SerializeField] private float _bendDuration = 0.3f;
        [SerializeField] private float _returnDuration = 1f;
        [SerializeField] private float _maxBendAngle = 15f;

        private Quaternion _initialRotation;

        private void Awake()
        {
            _initialRotation = transform.rotation;
        }

        private void OnCollisionEnter(Collision collision)
        {
            if (!collision.gameObject.CompareTag("Player")) return;

            Vector3 contactPoint = collision.contacts[0].point;
            Vector3 hitDir = (contactPoint - transform.position).normalized; 
            float direction = Mathf.Sign(hitDir.x);
        
            StopAllCoroutines();
            StartCoroutine(BendRoutine(direction));
        }

        private IEnumerator BendRoutine(float direction)
        {
            yield return BendTo(_maxBendAngle * direction, _bendDuration);
            yield return BendTo(-_maxBendAngle * direction * 0.3f, _returnDuration * 0.4f);
            yield return BendTo(0f, _returnDuration * 0.6f);
            transform.rotation = _initialRotation;
        }

        private IEnumerator BendTo(float targetAngle, float duration)
        {
            Quaternion start = transform.rotation;
            Quaternion target = _initialRotation * Quaternion.Euler(0f, 0f, targetAngle);
            float elapsed = 0f;

            while (elapsed < duration)
            {
                elapsed += Time.deltaTime;
                float t = EaseOutBack(Mathf.Clamp01(elapsed / duration));
                transform.rotation = Quaternion.Lerp(start, target, t);
                yield return null;
            }
        }

        private float EaseOutBack(float t)
        {
            const float c1 = 1.70158f;
            const float c3 = c1 + 1f;
            return 1 + c3 * Mathf.Pow(t - 1, 3) + c1 * Mathf.Pow(t - 1, 2);
        }
    }
}