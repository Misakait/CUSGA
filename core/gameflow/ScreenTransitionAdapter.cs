using System.Threading.Tasks;
using Godot;

namespace CUSGA.core.gameflow;

public sealed class ScreenTransitionAdapter(Node awaiter, Node screenTransitions)
{
    public Task FadeOutAsync()
    {
        return RunAsync("fade_out", "fade_complete");
    }

    public Task FadeInAsync()
    {
        return RunAsync("fade_in", "fade_in_complete");
    }

    private async Task RunAsync(string methodName, string completedSignal)
    {
        if (screenTransitions == null || !screenTransitions.HasMethod(methodName))
        {
            return;
        }

        screenTransitions.Call(methodName);
        await awaiter.ToSignal(screenTransitions, completedSignal);
    }
}
