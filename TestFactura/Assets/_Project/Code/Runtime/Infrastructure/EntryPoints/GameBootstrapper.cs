using System;
using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.StaticData;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.EntryPoints
{
    public class GameBootstrapper : MonoBehaviour
    {
        private ISceneLoader _sceneLoader;
        private ILoadingCurtain _loadingCurtain;
        private IStaticDataService _staticDataService;
        
        [Inject]
        private void Construct(ISceneLoader sceneLoader, ILoadingCurtain loadingCurtain
            , IStaticDataService staticDataService)
        {
            _sceneLoader = sceneLoader;
            _loadingCurtain = loadingCurtain;
            _staticDataService = staticDataService;
        }

        private void Awake()
        {
            _staticDataService.Initialize();
            
            _loadingCurtain.Appear();
            _sceneLoader.Load(SceneList.Gameplay);
            DontDestroyOnLoad(gameObject);
        }
    }
}