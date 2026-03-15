using _Project.Code.Runtime.GameLogic.Bullet;
using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.GameLogic.Camera;
using _Project.Code.Runtime.GameLogic.Car;
using _Project.Code.Runtime.GameLogic.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using _Project.Code.Runtime.UI.Windows;
using UnityEngine;

namespace _Project.Code.Runtime.Factory
{
    public interface IGameFactory
    {
        ICar CreateCar(Vector3 at, Vector3 destinationPosition);
        ICamera CreateCamera();
        ITurret CreateTurret();
        IBullet CreateBullet(IBulletPool bulletPool, Transform under);
        BaseWindow CreateWindow(WindowId windowId);
    }
}