using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace _Project.Code.Runtime.GameLogic.DistаnceIndicator
{
    public class DistanceIndicator : IDistanceIndicator
    {
        private readonly Image _indicatorFillImage;
        private readonly RectTransform _pointerRect;
        private readonly TextMeshProUGUI _distanceText;

        private float _start;
        private float _end;
        private Transform _target;
        
        public DistanceIndicator(Image indicatorFillImage, RectTransform pointerRect
            , TextMeshProUGUI distanceText)
        {
            _indicatorFillImage = indicatorFillImage;
            _pointerRect = pointerRect;
            _distanceText = distanceText;
        }
        
        public void Setup(float start, float end, Transform target)
        {
            _start = start;
            _end = end;
            _target = target;
            
            float progress = GetProgress();
            UpdateFill(progress);
        }

        public void Tick()
        {
            float progress = GetProgress();

            UpdateFill(progress);
            UpdatePointerPosition(progress);
            UpdateText();
        }

        private float GetProgress() => 
            Mathf.InverseLerp(_start, _end, _target.position.z);
        
        private void UpdateFill(float progress) => 
            _indicatorFillImage.fillAmount = Mathf.Lerp(_indicatorFillImage.fillAmount, progress, Time.deltaTime);

        private void UpdateText()
        {
            float distance = _target.position.z - _start;
            _distanceText.text = Mathf.Max(0, distance).ToString("0") + " m";
        }

        private void UpdatePointerPosition(float progress)
        {
            float height = _indicatorFillImage.rectTransform.rect.height;
            float y = Mathf.Lerp(-height * 0.5f, height * 0.5f, progress);
            _pointerRect.anchoredPosition = new Vector2(_pointerRect.anchoredPosition.x, y);
        }
    }
}