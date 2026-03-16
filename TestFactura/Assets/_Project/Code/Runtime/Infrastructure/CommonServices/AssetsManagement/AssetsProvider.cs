using UnityEngine;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement
{
    public class AssetsProvider : IAssetsProvider
    {
        public T Load<T>(string path) where T : Object => 
            Resources.Load<T>(path);
    }
}