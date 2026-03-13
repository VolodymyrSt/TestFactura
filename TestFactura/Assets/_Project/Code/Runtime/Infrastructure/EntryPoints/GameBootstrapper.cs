using System;
using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.EntryPoints
{
    public class GameBootstrapper : MonoBehaviour
    {
        private ISceneLoader _sceneLoader;
        private ILoadingCurtain _loadingCurtain;
        
        [Inject]
        private void Construct(ISceneLoader sceneLoader, ILoadingCurtain loadingCurtain)
        {
            _sceneLoader = sceneLoader;
            _loadingCurtain = loadingCurtain;
        }

        private void Awake()
        {
            //some stuff
            _loadingCurtain.Appear();
            _sceneLoader.Load(SceneList.Gameplay);
            DontDestroyOnLoad(gameObject);
        }
    }
}