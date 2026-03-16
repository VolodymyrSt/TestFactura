namespace _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement
{
    public interface IWindowService
    {
        void Open(WindowId windowId);
        void Close(WindowId windowId);
    }
}