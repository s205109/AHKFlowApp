namespace AHKFlowApp.UI.Blazor.Startup;

/// <summary>
/// Carries the config-time <see cref="StartupErrorReason"/> to the <see cref="StartupError"/>
/// root component when the app boots into an error state (registered as a singleton in Program.cs).
/// </summary>
internal sealed class StartupErrorState(StartupErrorReason reason)
{
    public StartupErrorReason Reason { get; } = reason;
}
