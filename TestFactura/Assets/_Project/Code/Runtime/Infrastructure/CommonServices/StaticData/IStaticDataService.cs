using _Project.Code.Runtime.Configs.Car;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.StaticData
{
    public interface IStaticDataService
    {
        CarConfigSO CarConfig { get; }
        void Initialize();
    }
}