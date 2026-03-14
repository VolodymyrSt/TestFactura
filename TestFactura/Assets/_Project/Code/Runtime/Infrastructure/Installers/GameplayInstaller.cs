using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.Installers
{
    public class GameplayInstaller : MonoInstaller
    {
        public override void InstallBindings()
        {
            BindGameFactory();
            BindInputService();
            BindBulletPool();
        }

        private void BindBulletPool() => 
            Container.BindInterfacesTo<BulletPool>().AsSingle();

        private void BindInputService() => 
            Container.BindInterfacesTo<InputService>().AsSingle();

        private void BindGameFactory() => 
            Container.BindInterfacesTo<GameFactory>().AsSingle();
    }
}