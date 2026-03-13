using _Project.Code.Runtime.Configs.Car;
using _Project.Code.Runtime.Configs.Turret;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.StaticData
{
    public interface IStaticDataService
    {
        CarConfigSO CarConfig { get; }
        TurretConfigSO TurretConfig { get; }
        void Initialize();
    }
}