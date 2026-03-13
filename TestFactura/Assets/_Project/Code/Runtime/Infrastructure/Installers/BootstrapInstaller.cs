using _Project.Code.Runtime.Infrastructure.CommonServices.SceneLoaderService;
using _Project.Code.Runtime.Utils;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.Installers
{
    public class BootstrapInstaller : MonoInstaller, ICoroutineRunner
    {
        public override void InstallBindings()
        {
            BindCoroutineRunner();
            BindSceneLoader();
        }

        private void BindCoroutineRunner() => 
            Container.Bind<ICoroutineRunner>().FromInstance(this).AsSingle();

        private void BindSceneLoader() => 
            Container.BindInterfacesTo<SceneLoader>().AsSingle();
    }
}
