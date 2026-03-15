using _Project.Code.Runtime.Configs.Turret;
using _Project.Code.Runtime.GameLogic.Bullet;
using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.GameLogic.Camera;
using _Project.Code.Runtime.GameLogic.Car;
using _Project.Code.Runtime.GameLogic.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.StaticData;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using _Project.Code.Runtime.UI.Windows;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Factory
{
    public class GameFactory : IGameFactory
    {
        private readonly IAssetsProvider _assetsProvider;
        private readonly IInstantiator _instantiator;
        private readonly IStaticDataService _staticDataService;
        private readonly RectTransform _uiRoot;
        
        public GameFactory(IAssetsProvider assetsProvider, IInstantiator instantiator
            , IStaticDataService staticDataService, RectTransform uiRoot)
        {
            _assetsProvider = assetsProvider;
            _instantiator = instantiator;
            _staticDataService = staticDataService;
            _uiRoot = uiRoot;
        }

        public ICar CreateCar(Vector3 at, Vector3 destinationPosition)
        {
            CarHandler carHandlerPrefab = _assetsProvider.Load<CarHandler>(AssetPath.Car);
            ICar carInstance = _instantiator.InstantiatePrefabForComponent<CarHandler>(carHandlerPrefab, at, Quaternion.identity, null);
            carInstance.SetUp(destinationPosition, _staticDataService.CarConfig);
            return carInstance;
        }
        
        public ITurret CreateTurret()
        {
            TurretHandler turretPrefab = _assetsProvider.Load<TurretHandler>(AssetPath.Turret);
            ITurret turretInstance = _instantiator.InstantiatePrefabForComponent<TurretHandler>(turretPrefab);
            TurretConfigSO turretConfig = _staticDataService.TurretConfig;
            turretInstance.Init(turretConfig);
            return turretInstance;
        }
        
        public ICamera CreateCamera()
        {
            CameraHandler cameraPrefab = _assetsProvider.Load<CameraHandler>(AssetPath.Camera);
            ICamera cameraInstance = _instantiator.InstantiatePrefabForComponent<CameraHandler>(cameraPrefab);
            return cameraInstance;
        }
        
        public IBullet CreateBullet(IBulletPool bulletPool, Transform under)
        {
            BulletHandler bulletPrefab = _assetsProvider.Load<BulletHandler>(AssetPath.Bullet);
            IBullet bulletInstance = _instantiator.InstantiatePrefabForComponent<BulletHandler>(bulletPrefab, under);
            bulletInstance.Init(bulletPool);
            return bulletInstance;
        }
        
        public BaseWindow CreateWindow(WindowId windowId) =>
            _instantiator.InstantiatePrefabForComponent<BaseWindow>(PrefabFor(windowId), _uiRoot);
        
        private GameObject PrefabFor(WindowId id) =>
            _staticDataService.GetWindowPrefab(id);
    }
}