using _Project.Code.Runtime.Configs.Car;
using _Project.Code.Runtime.Configs.Enemy;
using _Project.Code.Runtime.Configs.Turret;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.StaticData
{
    public interface IStaticDataService
    {
        CarConfigSO CarConfig { get; }
        TurretConfigSO TurretConfig { get; }
        EnemyConfigSO EnemyConfig { get; }
        void Initialize();
    }
}