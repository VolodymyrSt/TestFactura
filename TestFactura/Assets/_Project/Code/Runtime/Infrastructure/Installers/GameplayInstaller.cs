using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.Installers
{
    public class GameplayInstaller : MonoInstaller
    {
        public override void InstallBindings()
        {
            BindCarFactory();
            BindInputService();
        }

        private void BindInputService() => 
            Container.BindInterfacesTo<InputService>().AsSingle();

        private void BindCarFactory() => 
            Container.BindInterfacesTo<GameFactory>().AsSingle();
    }
}