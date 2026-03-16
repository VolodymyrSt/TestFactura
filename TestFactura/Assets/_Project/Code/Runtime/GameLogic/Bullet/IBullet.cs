using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Bullet
{
    public interface IBullet
    {
        void Init(IBulletPool bulletPool);
        void SetActive(bool active);
        void Fire(Vector3 direction, float force, float lifeTime, float damage);
        void Warp(Transform warpPoint);
        void Reset();
    }
}