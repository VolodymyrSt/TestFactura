using System;
using UnityEngine;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.Input
{
    public interface IInputService
    {
        Vector2 GetSwipeDelta();
        void Enable();
        void Disable();
        event Action OnScreenTouched;
    }
}