using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Car
{
    public interface ICar
    {
        void SetUp(Vector3 warpPoint, Vector3 destinationPoint, float moveSpeed);
        void StartMoving();
        Transform CameraTarget { get; }
        Transform TurretInstallPoint { get; }
    }
}