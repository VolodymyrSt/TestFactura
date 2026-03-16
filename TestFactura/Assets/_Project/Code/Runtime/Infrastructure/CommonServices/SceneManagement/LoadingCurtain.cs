using System;
using System.Collections;
using UnityEngine;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.SceneManagement
{
    public class LoadingCurtain: MonoBehaviour, ILoadingCurtain
    {
        [SerializeField] private CanvasGroup _canvasGroup;
        [SerializeField] private float _fadeDuration = 1f;
        [SerializeField] private float _durationBeforeFadeIn = 2f;

        public void Appear()
        {
            gameObject.SetActive(true);
            _canvasGroup.alpha = 1f;
            StartCoroutine(WaitAndFadeIn(_durationBeforeFadeIn));
        }

        private IEnumerator WaitAndFadeIn(float waitTime)
        {
            yield return new WaitForSeconds(waitTime);
            StartFade(() => gameObject.SetActive(false));
        }

        private void StartFade(Action onComplete) => 
            StartCoroutine(FadeRoutine(onComplete));

        private IEnumerator FadeRoutine(Action onComplete)
        {
            float elapsed = 0f;

            while (_fadeDuration > elapsed)
            {
                _canvasGroup.alpha -= 0.01f;
                elapsed += 0.01f;
                yield return new WaitForEndOfFrame();
            }

            onComplete?.Invoke();
        }
    }
}