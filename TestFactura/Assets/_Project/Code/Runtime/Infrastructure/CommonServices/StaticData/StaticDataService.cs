using System;
using System.Collections.Generic;
using System.Linq;
using _Project.Code.Runtime.Configs.Car;
using _Project.Code.Runtime.Configs.Enemy;
using _Project.Code.Runtime.Configs.Turret;
using _Project.Code.Runtime.Configs.Window;
using _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using UnityEngine;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.StaticData
{
    public class StaticDataService : IStaticDataService
    {
        private Dictionary<WindowId, GameObject> _windowPrefabsById;
        
        private readonly IAssetsProvider _assetsProvider;
        
        private CarConfigSO _carConfig;
        private TurretConfigSO _turretConfig;
        private EnemyConfigSO _enemyConfig;
        
        public CarConfigSO CarConfig => _carConfig;
        public EnemyConfigSO EnemyConfig => _enemyConfig;
        public TurretConfigSO TurretConfig => _turretConfig;
        
        public StaticDataService(IAssetsProvider assetsProvider) =>
            _assetsProvider = assetsProvider;

        public void Initialize()
        {
            _carConfig = _assetsProvider.Load<CarConfigSO>(AssetPath.CarConfig);
            _turretConfig = _assetsProvider.Load<TurretConfigSO>(AssetPath.TurretConfig);
            _enemyConfig = _assetsProvider.Load<EnemyConfigSO>(AssetPath.EnemyConfig);
            _windowPrefabsById = _assetsProvider.Load<WindowConfigsSO>(AssetPath.WindowConfigs)
                .WindowConfigs
                .ToDictionary(x => x.Id, x => x.Prefab);
        }
        
        public GameObject GetWindowPrefab(WindowId id) =>
            _windowPrefabsById.TryGetValue(id, out GameObject prefab)
                ? prefab
                : throw new Exception($"Prefab config for window {id} was not found");
    }
}