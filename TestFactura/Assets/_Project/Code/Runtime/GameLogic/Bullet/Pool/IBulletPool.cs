using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Bullet.Pool
{
    public interface IBulletPool
    {
        void Preload(int initialCount);
        IBullet Get();
        void Release(IBullet bullet);
    }
}