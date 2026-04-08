using System.Reflection;

namespace AHKFlowApp.Infrastructure.Services;

public sealed class VersionService : IVersionService
{
    private readonly string _version = Assembly.GetEntryAssembly()?
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
        .InformationalVersion ?? "0.0.0-dev";

    public ValueTask<string> GetVersionAsync(CancellationToken cancellationToken = default)
    {
        if (cancellationToken.IsCancellationRequested)
            return ValueTask.FromCanceled<string>(cancellationToken);
        return ValueTask.FromResult(_version);
    }
}
