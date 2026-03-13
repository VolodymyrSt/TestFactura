using UnityEngine;

namespace _Project.Code.Runtime.GameLogic.Turret
{
    public class TurretHandler : MonoBehaviour, ITurret
    {
        public void InstallOn(Transform installPoint)
        {
            transform.SetParent(installPoint, false);
            transform.localPosition = Vector3.zero;
        }
    }
}