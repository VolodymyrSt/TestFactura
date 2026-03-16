using System.Collections.Generic;
using _Project.Code.Runtime.Factory;
using ModestTree;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Bullet.Pool
{
    public class BulletPool : IBulletPool
    {
        private readonly Queue<IBullet> _pooledBullets = new();
        private readonly IGameFactory _factory;

        private Transform _holder;
        private Transform Holder => _holder ??= new GameObject("BulletHolder").transform ;
        
        public BulletPool(IGameFactory factory) => 
            _factory = factory;
        
        public void Preload(int initialCount)
        {
            for (int i = 0; i < initialCount; i++)
            {
                IBullet bullet = _factory.CreateBullet(this, Holder);
                Release(bullet);
            }
        }

        public IBullet Get()
        {
            IBullet bullet;
            
            if (_pooledBullets.IsEmpty())
                bullet = _factory.CreateBullet(this, Holder);
            else
            {
                bullet = _pooledBullets.Dequeue();
                bullet.Reset();
                bullet.SetActive(true);
            }

            return bullet;
        }
        
        public void Release(IBullet bullet)
        {
            bullet.SetActive(false);
            _pooledBullets.Enqueue(bullet);
        }
    }
}