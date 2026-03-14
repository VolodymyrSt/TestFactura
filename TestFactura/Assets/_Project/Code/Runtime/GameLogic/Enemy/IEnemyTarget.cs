using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Enemy
{
    public interface IEnemyTarget : IDamageable
    {
        bool IsAlive { get; }
        Transform Transform { get; }
    }
}