using System.Collections.Generic;
using _Project.Code.Runtime.Factory;
using _Project.Code.Runtime.UI.Windows;
using UnityEngine;

namespace _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement
{
    public class WindowService : IWindowService
    {
        private readonly IGameFactory _gameFactory;

        private readonly List<BaseWindow> _openedWindows = new();

        public WindowService(IGameFactory gameFactory) =>
            _gameFactory = gameFactory;

        public void Open(WindowId windowId) => 
            _openedWindows.Add(_gameFactory.CreateWindow(windowId));

        public void Close(WindowId windowId)
        {
            BaseWindow window = _openedWindows.Find(x => x.Id == windowId);
            if (window == null) return;

            _openedWindows.Remove(window);
            Object.Destroy(window.gameObject);
        }
    }
}