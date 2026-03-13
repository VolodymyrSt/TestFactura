using UnityEngine;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.AssetsManagement
{
    public interface IAssetsProvider
    {
        T Load<T>(string path) where T : Object;
    }
}