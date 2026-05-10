namespace AHKFlowApp.CLI.Services;

public sealed class BinaryStdout(Func<Stream>? factory = null)
{
    private readonly Func<Stream> _factory = factory ?? Console.OpenStandardOutput;

    public Stream Open() => _factory();
}
