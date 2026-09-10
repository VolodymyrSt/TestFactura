using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(Renderer))]
public class WindStrengthBlock : MonoBehaviour
{
    [Header("Individual Tree Settings")]
    [Range(0f, 5f)] 
    [SerializeField] private float treeWindStrength = 1.0f;
    
    private Renderer _renderer;
    private MaterialPropertyBlock _propBlock;
    
    // Стовідсоткове влучання в ім'я властивості з шейдера
    private static readonly int WindStrengthProp = Shader.PropertyToID("_WindStrength");

    void OnValidate()
    {
        UpdateWind();
    }

    void Update()
    {
        UpdateWind();
    }

    private void UpdateWind()
    {
        if (_renderer == null) _renderer = GetComponent<Renderer>();
        if (_propBlock == null) _propBlock = new MaterialPropertyBlock();

        _renderer.GetPropertyBlock(_propBlock);
        
        _propBlock.SetFloat(WindStrengthProp, treeWindStrength);
        
        _renderer.SetPropertyBlock(_propBlock);
    }
}