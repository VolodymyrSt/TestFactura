using System;
using _Project.Code.Runtime.GameLogic.HealthLogic;
using UnityEngine;
using UnityEngine.UI;

namespace _Project.Code.Runtime.UI.HealthBar
{
    public class HealthBarView : MonoBehaviour
    {
        [SerializeField] private Image _healthSlider;

        private HealthSystem _healthSystem;

        public void Bind(HealthSystem healthSystem)
        {
            _healthSystem = healthSystem;
            _healthSystem.OnHealthChanged += UpdateBar;
            
            _healthSlider.fillAmount = _healthSystem.Max / _healthSystem.Current;
        }

        private void UpdateBar(float currentHealth) =>
            _healthSlider.fillAmount = Mathf.Clamp01(currentHealth / _healthSystem.Max);

        private void OnDestroy() => 
            _healthSystem.OnHealthChanged -= UpdateBar;
    }
}