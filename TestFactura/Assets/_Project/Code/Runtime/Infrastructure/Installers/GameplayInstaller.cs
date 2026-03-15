using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.Installers
{
    public class GameplayInstaller : MonoInstaller
    {
        [SerializeField] private RectTransform _uiRoot;
        
        public override void InstallBindings()
        {
            BindGameFactory();
            BindInputService();
            BindBulletPool();
            BindWindowService();
        }

        private void BindWindowService() =>
            Container.BindInterfacesTo<WindowService>().AsSingle();

        private void BindBulletPool() => 
            Container.BindInterfacesTo<BulletPool>().AsSingle();

        private void BindInputService() => 
            Container.BindInterfacesTo<InputService>().AsSingle();

        private void BindGameFactory() => 
            Container.BindInterfacesTo<GameFactory>().AsSingle().WithArguments(_uiRoot);
    }
}