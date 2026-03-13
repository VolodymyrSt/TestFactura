using _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using _Project.Code.Runtime.Utils;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.Installers
{
    public class BootstrapInstaller : MonoInstaller, ICoroutineRunner
    {
        [SerializeField] private LoadingCurtain _loadingCurtain;
        
        public override void InstallBindings()
        {
            BindCoroutineRunner();
            BindSceneLoader();
            BindAssetsProvider();
            BindLoadingCurtain();
        }

        private void BindLoadingCurtain() => 
            Container.Bind<ILoadingCurtain>().FromComponentInNewPrefab(_loadingCurtain).AsSingle();

        private void BindAssetsProvider() => 
            Container.BindInterfacesTo<AssetsProvider>().AsSingle();

        private void BindCoroutineRunner() => 
            Container.Bind<ICoroutineRunner>().FromInstance(this).AsSingle();

        private void BindSceneLoader() => 
            Container.BindInterfacesTo<SceneLoader>().AsSingle();
    }
}
