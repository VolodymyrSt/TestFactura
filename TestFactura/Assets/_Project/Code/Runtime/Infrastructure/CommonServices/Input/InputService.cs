using UnityEngine;
using UnityEngine.InputSystem;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.Input
{
    public class InputService : IInputService
    {
        private readonly PlayerInputAction _inputAction; 
        
        public InputService() => 
            _inputAction = new PlayerInputAction();

        public Vector2 GetLookInput() =>
            _inputAction.Player.Look.ReadValue<Vector2>();
    }
}