using _Project.Code.Runtime.Infrastructure.CommonServices.WindowManagement;

namespace _Project.Code.Runtime.UI.Windows.Tutorial
{
    public class TutorialWindow : BaseWindow
    {
        protected override void Initialize()
        {
            Id = WindowId.Tutorial;
        }
    }
}