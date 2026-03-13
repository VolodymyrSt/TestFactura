using UnityEngine;
using UnityEngine.AI;

namespace _Project.Code.Runtime.GameLogic.Car
{
    public class CarHandler : MonoBehaviour, ICar
    {
        [Header("Base")]
        [SerializeField] private NavMeshAgent _agent;
        
        [Header("Turret Installation")]
        [SerializeField] private Transform _turretInstallPoint;
        
        public Transform CameraTarget => transform;
        public Transform TurretInstallPoint => _turretInstallPoint;
        
        private void OnValidate() => 
            _agent ??= GetComponent<NavMeshAgent>();

        public void SetUp(Vector3 warpPoint, Vector3 destinationPoint,
            float moveSpeed)
        {
            _agent.Warp(warpPoint);
            _agent.SetDestination(destinationPoint);
            _agent.speed = moveSpeed;
            _agent.isStopped = true;
        }

        public void StartMoving() => 
            _agent.isStopped = false;
    }
}