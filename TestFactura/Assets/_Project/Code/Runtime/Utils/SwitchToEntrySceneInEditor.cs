using _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using Zenject;

namespace _Project.Code.Runtime.Utils
{
    //this script help us to start game with Bootstrap scene
    public class SwitchToEntrySceneInEditor : MonoBehaviour
    {
#if UNITY_EDITOR
        private void Awake()
        {
            if (ProjectContext.HasInstance)
                return;
      
            foreach (GameObject root in gameObject.scene.GetRootGameObjects()) 
                root.SetActive(false);

            SceneManager.LoadScene(SceneList.Bootstrap);
        }
#endif
    }
}