using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using DG.Tweening;
using UnityEngine;

namespace _Project.Code.Runtime.UI.Windows.Tutorial
{
    public class TutorialWindow : BaseWindow
    {
        [SerializeField] private RectTransform _aimRect;
        [SerializeField] private float _swipeDistance = 450f;
        [SerializeField] private float _swipeDuration = 2f;
        
        protected override void Initialize()
        {
            Id = WindowId.Tutorial;
            
            _aimRect.anchoredPosition = new Vector2(-_swipeDistance, _aimRect.anchoredPosition.y);
            
            _aimRect.DOAnchorPosX(_swipeDistance, _swipeDuration)
                .SetEase(Ease.Linear)
                .SetLoops(-1, LoopType.Yoyo)
                .Play();
        }
    }
}