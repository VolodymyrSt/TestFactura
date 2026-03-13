using _Project.Code.Runtime.GameLogic.Camera;
using _Project.Code.Runtime.GameLogic.Car;
using _Project.Code.Runtime.GameLogic.Turret;
using UnityEngine;

namespace _Project.Code.Runtime.Factory
{
    public interface IGameFactory
    {
        ICar CreateCar(Vector3 warpPosition, Vector3 destinationPosition);
        ICamera CreateCamera();
        ITurret CreateTurret();
    }
}