using System;
using _Project.Code.Runtime.Configs.Car;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Car
{
    public interface ICar
    {
        void SetUp(Vector3 destinationPosition, CarConfigSO config);
        void StartMoving();
        Transform CameraTarget { get; }
        Transform TurretInstallPoint { get; }
        event Action OnDestroyed;
        event Action OnReachedDestination;
    }
}