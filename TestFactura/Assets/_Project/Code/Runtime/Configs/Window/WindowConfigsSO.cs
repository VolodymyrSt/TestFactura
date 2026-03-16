using System;
using System.Collections.Generic;
using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;
using UnityEngine;

namespace _Project.Code.Runtime.Configs.Window
{
    [CreateAssetMenu(fileName = "WindowConfigs", menuName = "Configs/Window/WindowConfigs")]
    public class WindowConfigsSO : ScriptableObject
    {
        public List<WindowConfig> WindowConfigs;
    }
    
    [Serializable]
    public class WindowConfig
    {
        public WindowId Id;
        public GameObject Prefab;
    }
}