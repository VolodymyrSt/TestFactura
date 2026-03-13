using System;
using System.Collections;
using _Project.Code.Runtime.Utils;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.SceneLoaderService
{
    public class SceneLoader : ISceneLoader
    {
        private readonly ICoroutineRunner _coroutineRunner;

        public SceneLoader(ICoroutineRunner coroutineRunner) => 
            _coroutineRunner = coroutineRunner;

        public void Load(string sceneName, Action onLoaded = null) => 
            _coroutineRunner.StartCoroutine(LoadScene(sceneName, onLoaded));

        private IEnumerator LoadScene(string sceneName, Action onLoaded = null)
        {
            if (SceneManager.GetActiveScene().name == sceneName)
            {
                onLoaded?.Invoke();
                yield break;
            }

            AsyncOperation wait = SceneManager.LoadSceneAsync(sceneName);

            while (!wait.isDone)
                yield return wait;

            onLoaded?.Invoke();
        }
    }
}