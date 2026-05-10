namespace AHKFlowApp.CLI.Services;

public sealed class WorkingDirectory(Func<string>? factory = null)
{
    private readonly Func<string> _factory = factory ?? (() => Environment.CurrentDirectory);

    public string Get() => _factory();
}
