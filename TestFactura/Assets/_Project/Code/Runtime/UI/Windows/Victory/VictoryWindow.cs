using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
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
        
        private ISceneLoader _sceneLoader;
        private ILoadingCurtain _loadingCurtain;
        private IInputService _inputService;

        [Inject]
        private void Construct(ISceneLoader sceneLoader, ILoadingCurtain loadingCurtain
            , IInputService inputService)
        {
            _sceneLoader = sceneLoader;
            _loadingCurtain = loadingCurtain;
            _inputService = inputService;
        }

        protected override void Initialize()
        {
            Id = WindowId.Victory;

            PopupVictoryMessage();

            _inputService.OnScreenTouched += Replay;
        }

        private void Replay()
        {
            _loadingCurtain.Appear();
            _sceneLoader.Load(SceneList.Gameplay);
        }

        private void PopupVictoryMessage()
        {
            _victoryMassage.rectTransform.localScale = Vector3.zero;
            _victoryMassage.rectTransform.DOScale(endValue: 1f, duration: 0.5f)
                .SetEase(Ease.InOutBack)
                .Play();
        }

        protected override void Dispose() => 
            _inputService.OnScreenTouched -= Replay;
    }
}