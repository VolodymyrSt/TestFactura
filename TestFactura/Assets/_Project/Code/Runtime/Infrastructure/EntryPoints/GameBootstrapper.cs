using System;
using _Project.Code.Runtime.Infrastructure.CommonServices.SceneLoaderService;
using UnityEngine;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.EntryPoints
{
    public class GameBootstrapper : MonoBehaviour
    {
        private ISceneLoader _sceneLoader;
        
        [Inject]
        private void Construct(ISceneLoader sceneLoader) => 
            _sceneLoader = sceneLoader;

        private void Awake()
        {
            //some stuff
            // _sceneLoader.Load(SceneList.Gameplay);
            DontDestroyOnLoad(gameObject);
        }
    }
}