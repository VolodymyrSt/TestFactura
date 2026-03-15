using System;
using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.GameLogic.Barrier;
using _Project.Code.Runtime.GameLogic.Camera;
using _Project.Code.Runtime.GameLogic.Car;
using _Project.Code.Runtime.GameLogic.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.EntryPoints
{
    public class GameplayEntryPoint : MonoBehaviour
    {
        [Header("Car Settings:")]
        [SerializeField] private Transform _carWarpPoint;
        [SerializeField] private Transform _carDestinationPoint;
        
        [Header("Barriers:")]
        [SerializeField] private BarriersHandler _barriers;
        
        private IGameFactory _gameFactory;
        private IInputService _inputService;
        private IWindowService _windowService;

        private ICar _car;
        private ITurret _turret;
        
        [Inject]
        private void Construct(IGameFactory gameFactory, IInputService inputService
            ,IWindowService windowService)
        {
            _gameFactory = gameFactory;
            _inputService = inputService;
            _windowService = windowService;
        }

        private void Awake()
        {
            _inputService.Enable();
            
            _inputService.OnScreenTouched += StartGameplay;
                
            _car = _gameFactory.CreateCar(_carWarpPoint.position, _carDestinationPoint.position);
            _turret = _gameFactory.CreateTurret();
            ICamera camera = _gameFactory.CreateCamera();
            
            _car.OnDestroyed += OnGameLost;
            _car.OnReachedDestination += OnGameWon;
            
            camera.SetTarget(_car.CameraTarget);
            _turret.InstallOn(_car.TurretInstallPoint);
            
            _windowService.Open(WindowId.Tutorial);
        }

        private void OnGameLost()
        {
            _windowService.Open(WindowId.Defeat);
            _turret.Deactivate();
            _inputService.Disable();
        }
        
        private void OnGameWon()
        {
            _windowService.Open(WindowId.Victory);
            _turret.Deactivate();
            _inputService.Disable();
        }

        private void StartGameplay()
        {
            _windowService.Close(WindowId.Tutorial);
            _barriers.Open();
            
            _car.StartMoving();
            _turret.Activate();
        }

        private void OnDestroy()
        {
            _inputService.OnScreenTouched -= StartGameplay;
            _car.OnDestroyed -= OnGameLost;
            _car.OnReachedDestination -= OnGameWon;
        }
    }
}