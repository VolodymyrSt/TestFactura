using System;
using UnityEngine;
using UnityEngine.InputSystem;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.Input
{
    public class InputService : IInputService, IDisposable
    {
        public event Action OnScreenTouched;
        
        private readonly PlayerInputAction _inputAction = new();

        public void Enable()
        {
            _inputAction.Enable();
            
            _inputAction.Player.Touch.performed += OnTouchPerformed;
        }
        
        public void Disable()
        {
            _inputAction.Disable();
            
            _inputAction.Player.Touch.performed -= OnTouchPerformed;
        }

        private void OnTouchPerformed(InputAction.CallbackContext obj) => 
            OnScreenTouched?.Invoke();
        
        public Vector2 GetSwipeDelta() =>
            _inputAction.Player.SwipeDelta.ReadValue<Vector2>();

        public void Dispose() =>
            Disable();
    }
}