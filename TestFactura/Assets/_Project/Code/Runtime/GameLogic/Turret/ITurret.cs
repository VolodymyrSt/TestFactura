using _Project.Code.Runtime.Configs.Turret;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Turret
{
    public interface ITurret
    {
        void InstallOn(Transform installPoint);
        void Init(TurretConfigSO config);
    }
}