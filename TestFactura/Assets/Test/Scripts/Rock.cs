using UnityEngine;

namespace Test.Scripts
{
    public class Rock : MonoBehaviour
    {
        [SerializeField] private string _propertyName = "_MyFloatValue";
        [SerializeField] private float _value = 1.0f;

        private Renderer _renderer;
        private MaterialPropertyBlock _propBlock;

        void Awake()
        {
            _renderer = GetComponent<Renderer>();
            _propBlock = new MaterialPropertyBlock();
        }

        void Update()
        {
            _renderer.GetPropertyBlock(_propBlock);
        
            _propBlock.SetFloat(_propertyName, _value);
        
            _renderer.SetPropertyBlock(_propBlock);
        }
    }
}