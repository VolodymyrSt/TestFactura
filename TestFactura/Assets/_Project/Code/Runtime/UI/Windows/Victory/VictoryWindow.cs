using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using DG.Tweening;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using Zenject;

namespace _Project.Code.Runtime.UI.Windows.Victory
{
    public class VictoryWindow : BaseWindow
    {
        [SerializeField] private TextMeshProUGUI _victoryMassage;
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

            PopupVictoryMessage();
            
            _restartButton.onClick.AddListener(() => {
                _loadingCurtain.Appear();
                _sceneLoader.Load(SceneList.Gameplay);
            });
        }

        private void PopupVictoryMessage()
        {
            _victoryMassage.rectTransform.localScale = Vector3.zero;
            _victoryMassage.rectTransform.DOScale(endValue: 1f, duration: 0.5f)
                .SetEase(Ease.InOutBack)
                .Play();
        }

        protected override void Dispose() => 
            _restartButton.onClick.RemoveAllListeners();
    }
}