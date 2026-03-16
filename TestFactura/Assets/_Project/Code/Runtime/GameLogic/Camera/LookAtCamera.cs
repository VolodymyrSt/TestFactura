using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Camera
{
    public class LookAtCamera : MonoBehaviour
    {
        private UnityEngine.Camera _camera;
        
        private void Start() => 
            _camera = UnityEngine.Camera.main;

        private void LateUpdate()
        {
            Vector3 direction = transform.position - _camera.transform.position;
            transform.rotation = Quaternion.LookRotation(direction, Vector3.up);
        }
    }
}