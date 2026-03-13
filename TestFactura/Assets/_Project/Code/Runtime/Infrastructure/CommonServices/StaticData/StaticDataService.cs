using _Project.Code.Runtime.Configs.Car;
using _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.StaticData
{
    public class StaticDataService : IStaticDataService
    {
        private readonly IAssetsProvider _assetsProvider;
        
        private CarConfigSO _carConfig;
        
        public CarConfigSO CarConfig => _carConfig;
        
        public StaticDataService(IAssetsProvider assetsProvider) =>
            _assetsProvider = assetsProvider;

        public void Initialize() => 
            _carConfig = _assetsProvider.Load<CarConfigSO>(AssetPath.CarConfig);
    }
}