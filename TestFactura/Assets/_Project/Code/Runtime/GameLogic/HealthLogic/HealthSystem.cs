using System;
using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.HealthLogic
{
    public class HealthSystem
    {
        public event Action<float> OnHealthChanged;
        private readonly float _max;
        private float _current;

        public float Current => _current;
        public float Max => _max;
        
        public HealthSystem(float maxHealth)
        {
            if (maxHealth < 0) 
                throw new Exception("MaxHealth cannot be less than 0");
            
            _max = maxHealth;
            _current = _max;
        }

        public void Reduce(float damage)
        {
            if (damage < 0) return;
            
            _current = Mathf.Clamp(_current - damage, 0, _max);
            OnHealthChanged?.Invoke(_current);
        }
    }
}