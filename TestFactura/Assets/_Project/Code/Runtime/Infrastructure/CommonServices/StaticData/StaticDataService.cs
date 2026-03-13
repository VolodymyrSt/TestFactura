using _Project.Code.Runtime.Configs.Car;
using _Project.Code.Runtime.Configs.Turret;
using _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.StaticData
{
    public class StaticDataService : IStaticDataService
    {
        private readonly IAssetsProvider _assetsProvider;
        
        private CarConfigSO _carConfig;
        private TurretConfigSO _turretConfig;
        
        public CarConfigSO CarConfig => _carConfig;
        public TurretConfigSO TurretConfig => _turretConfig;
        
        public StaticDataService(IAssetsProvider assetsProvider) =>
            _assetsProvider = assetsProvider;

        public void Initialize()
        {
            _carConfig = _assetsProvider.Load<CarConfigSO>(AssetPath.CarConfig);
            _turretConfig = _assetsProvider.Load<TurretConfigSO>(AssetPath.TurretConfig);
        }
    }
}