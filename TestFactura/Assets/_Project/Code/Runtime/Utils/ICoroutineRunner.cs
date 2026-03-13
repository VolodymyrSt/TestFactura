using System.Collections;
using UnityEngine;

namespace _Project.Code.Runtime.Utils
{
    public interface ICoroutineRunner 
    {
        Coroutine StartCoroutine(IEnumerator routine);
    }
}