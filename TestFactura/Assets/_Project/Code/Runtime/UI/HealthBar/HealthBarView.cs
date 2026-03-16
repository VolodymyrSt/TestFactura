using System;
using _Project.Code.Runtime.GameLogic.HealthLogic;
using UnityEngine;
using UnityEngine.UI;

namespace _Project.Code.Runtime.UI.HealthBar
{
    public class HealthBarView : MonoBehaviour
    {
        [SerializeField] protected RectTransform _root;
        [SerializeField] private Image _healthSlider;

        private HealthSystem _healthSystem;
        private bool _isActivated;

        public void Bind(HealthSystem healthSystem)
        {
            _healthSystem = healthSystem;
            _healthSystem.OnHealthChanged += UpdateBar;
            
            _healthSlider.fillAmount = _healthSystem.Max / _healthSystem.Current;
            
            _isActivated = false;
            _root.gameObject.SetActive(_isActivated);
        }

        private void UpdateBar(float currentHealth)
        {
            if (!_isActivated) {
                _isActivated = true;
                _root.gameObject.SetActive(_isActivated);
            }
            
            _healthSlider.fillAmount = Mathf.Clamp01(currentHealth / _healthSystem.Max);
        }

        private void OnDestroy() => 
            _healthSystem.OnHealthChanged -= UpdateBar;
    }
}