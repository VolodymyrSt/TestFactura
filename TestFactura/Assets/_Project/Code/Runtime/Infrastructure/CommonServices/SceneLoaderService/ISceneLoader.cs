using System;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.SceneLoaderService
{
    public interface ISceneLoader
    {
        void Load(string sceneName, Action onLoaded = null);
    }
}