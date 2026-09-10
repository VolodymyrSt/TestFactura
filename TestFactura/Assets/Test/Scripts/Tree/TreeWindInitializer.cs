using System;
using UnityEngine;
using Random = UnityEngine.Random;

using UnityEngine;

public class TreeWindInitializer : MonoBehaviour
{
    [Range(0f, 1f)] public float rootApp = 1.0f; 

    private Renderer _renderer;
    private MaterialPropertyBlock _mpb;

    private void Awake()
    {
        _renderer = GetComponent<Renderer>();
        _mpb = new MaterialPropertyBlock();
    }
    
    void Start()
    {
        _renderer.GetPropertyBlock(_mpb);

        _mpb.SetFloat("_RootStiffness", rootApp);

        _renderer.SetPropertyBlock(_mpb);
    }
}