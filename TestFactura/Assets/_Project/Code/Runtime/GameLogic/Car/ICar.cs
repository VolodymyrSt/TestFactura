using System;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Car
{
    public interface ICar
    {
        void SetUp(Vector3 warpPoint, Vector3 destinationPoint, float moveSpeed, float maxHealth);
        void StartMoving();
        Transform CameraTarget { get; }
        Transform TurretInstallPoint { get; }
        event Action OnDestroyed;
        event Action OnReachedEnd;
    }
}