using System;
using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.GameLogic.Camera;
using _Project.Code.Runtime.GameLogic.Car;
using _Project.Code.Runtime.GameLogic.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.EntryPoints
{
    public class GameplayEntryPoint : MonoBehaviour
    {
        [Header("Car Settings:")]
        [SerializeField] private Transform _carWarpPoint;
        [SerializeField] private Transform _carDestinationPoint;
        
        private IGameFactory _gameFactory;
        private IInputService _inputService;
        
        [Inject]
        private void Construct(IGameFactory gameFactory, IInputService inputService)
        {
            _gameFactory = gameFactory;
            _inputService = inputService;
        }

        private void Awake()
        {
            ICar car = _gameFactory.CreateCar(_carWarpPoint.position, _carDestinationPoint.position);
            ITurret turret = _gameFactory.CreateTurret();
            ICamera camera = _gameFactory.CreateCamera();
            
            camera.SetTarget(car.CameraTarget);
            turret.InstallOn(car.TurretInstallPoint);
            
            car.StartMoving();
        }
    }
}