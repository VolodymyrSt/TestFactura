using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.GameLogic.Bullet.Pool;
using _Project.Code.Runtime.GameLogic.DistаnceIndicator;
using _Project.Code.Runtime.Infrastructure.CommonServices.Input;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using Zenject;

namespace _Project.Code.Runtime.Infrastructure.Installers
{
    public class GameplayInstaller : MonoInstaller
    {
        [Header("Hub:")]
        [SerializeField] private RectTransform _uiRoot;
        
        [Header("DistanceIndicator:")]
        [SerializeField] private Image _indicatorFillImage;
        [SerializeField] private RectTransform _pointerRect;
        [SerializeField] private TextMeshProUGUI _distanceText;
        
        public override void InstallBindings()
        {
            BindGameFactory();
            BindInputService();
            BindBulletPool();
            BindWindowService();
            BindDistanceIndicator();
        }

        private void BindDistanceIndicator() => 
            Container.BindInterfacesTo<DistanceIndicator>().AsSingle()
                .WithArguments(_indicatorFillImage, _pointerRect, _distanceText);

        private void BindWindowService() =>
            Container.BindInterfacesTo<WindowService>().AsSingle();

        private void BindBulletPool() => 
            Container.BindInterfacesTo<BulletPool>().AsSingle();

        private void BindInputService() => 
            Container.BindInterfacesTo<InputService>().AsSingle();

        private void BindGameFactory() => 
            Container.BindInterfacesTo<GameFactory>().AsSingle().WithArguments(_uiRoot);
    }
}