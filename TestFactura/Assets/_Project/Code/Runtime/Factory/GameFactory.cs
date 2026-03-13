using _Project.Code.Runtime.GameLogic.Camera;
using _Project.Code.Runtime.GameLogic.Car;
using _Project.Code.Runtime.GameLogic.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.StaticData;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Factory
{
    public class GameFactory : IGameFactory
    {
        private readonly IAssetsProvider _assetsProvider;
        private readonly IInstantiator _instantiator;
        private readonly IStaticDataService _staticDataService;
        
        public GameFactory(IAssetsProvider assetsProvider, IInstantiator instantiator
            , IStaticDataService staticDataService)
        {
            _assetsProvider = assetsProvider;
            _instantiator = instantiator;
            _staticDataService = staticDataService;
        }

        public ICar CreateCar(Vector3 warpPosition, Vector3 destinationPosition)
        {
            CarHandler carHandlerPrefab = _assetsProvider.Load<CarHandler>(AssetPath.Car);
            ICar carInstance = _instantiator.InstantiatePrefabForComponent<CarHandler>(carHandlerPrefab);
            carInstance.SetUp(warpPosition, destinationPosition, _staticDataService.CarConfig.Speed);
            return carInstance;
        }
        
        public ITurret CreateTurret()
        {
            TurretHandler turretPrefab = _assetsProvider.Load<TurretHandler>(AssetPath.Turret);
            ITurret turretInstance = _instantiator.InstantiatePrefabForComponent<TurretHandler>(turretPrefab);
            return turretInstance;
        }
        
        public ICamera CreateCamera()
        {
            CameraHandler cameraPrefab = _assetsProvider.Load<CameraHandler>(AssetPath.Camera);
            ICamera cameraInstance = _instantiator.InstantiatePrefabForComponent<CameraHandler>(cameraPrefab);
            return cameraInstance;
        }
    }
}