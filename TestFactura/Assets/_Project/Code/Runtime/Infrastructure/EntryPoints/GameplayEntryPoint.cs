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

        private ICar _car;
        
        [Inject]
        private void Construct(IGameFactory gameFactory, IInputService inputService)
        {
            _gameFactory = gameFactory;
            _inputService = inputService;
        }

        private void Awake()
        {
            _inputService.Enable();
            
            _inputService.OnScreenTouched += InputServiceOnOnScreenTouched;
                
            _car = _gameFactory.CreateCar(_carWarpPoint.position, _carDestinationPoint.position);
            ITurret turret = _gameFactory.CreateTurret();
            ICamera camera = _gameFactory.CreateCamera();
            
            camera.SetTarget(_car.CameraTarget);
            turret.InstallOn(_car.TurretInstallPoint);
        }

        private void InputServiceOnOnScreenTouched()
        {
            _car.StartMoving();
        }
    }
}