using UnityEngine;

public class GlobalWindManager : MonoBehaviour
{
    public Transform playerTransform;
    
    [Header("Zone Settings")]
    public float zone1Start = 100f;
    public float zone2Start = 200f; 
    public float zone3Start = 300f;

    void Update()
    {
        float zPos = playerTransform.position.z;
        float currentStrength = 0;

        if (zPos >= zone3Start) 
            currentStrength = 1.0f;
        else if (zPos >= zone2Start) 
            currentStrength = 0.5f;
        else if (zPos >= zone1Start) 
            currentStrength = 0.2f;

        Shader.SetGlobalFloat("_GlobalWindStrength", currentStrength);
    }
}