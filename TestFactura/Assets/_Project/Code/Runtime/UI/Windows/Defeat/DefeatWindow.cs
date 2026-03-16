using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using DG.Tweening;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using Zenject;

namespace _Project.Code.Runtime.UI.Windows.Defeat
{
    public class DefeatWindow : BaseWindow
    {
        [SerializeField] private TextMeshProUGUI _defeatMassage;
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
            Id = WindowId.Defeat;

            PopupDefeatMessage();
            
            _restartButton.onClick.AddListener(() => {
                _loadingCurtain.Appear();
                _sceneLoader.Load(SceneList.Gameplay);
            });
        }
        
        private void PopupDefeatMessage()
        {
            _defeatMassage.rectTransform.localScale = Vector3.zero;
            _defeatMassage.rectTransform.DOScale(endValue: 1f, duration: 0.5f)
                .SetEase(Ease.InOutBack)
                .Play();
        }

        protected override void Dispose() => 
            _restartButton.onClick.RemoveAllListeners();
    }
}