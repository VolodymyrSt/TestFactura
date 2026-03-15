using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using UnityEngine;

namespace _Project.Code.Runtime.UI.Windows
{
    public class BaseWindow : MonoBehaviour
    {
        public WindowId Id {get; protected set;}
        
        private void Start() =>
            Initialize();
        
        private void OnDestroy() =>
            Dispose();

        protected virtual void Initialize() { }
        protected virtual void Dispose() {}
    }
}