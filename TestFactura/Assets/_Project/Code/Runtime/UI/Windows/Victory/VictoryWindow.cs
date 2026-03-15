using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using UnityEngine;
using UnityEngine.UI;
using Zenject;

namespace _Project.Code.Runtime.UI.Windows.Victory
{
    public class VictoryWindow : BaseWindow
    {
        [SerializeField] private Button _restartButton;
        
        private ISceneLoader _sceneLoader;
        private ILoadingCurtain _loadingCurtain;

        [Inject]
        private void Construct(ISceneLoader sceneLoader, ILoadingCurtain loadingCurtain)
        {
            _sceneLoader = sceneLoader;
            _loadingCurtain = loadingCurtain;
        }

        protected override void Initialize()
        {
            Id = WindowId.Victory;
            
            _restartButton.onClick.AddListener(() => {
                _loadingCurtain.Appear();
                _sceneLoader.Load(SceneList.Gameplay);
            });
        }

        protected override void Dispose() => 
            _restartButton.onClick.RemoveAllListeners();
    }
}