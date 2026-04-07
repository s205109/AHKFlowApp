using System.Reflection;

namespace AHKFlowApp.Infrastructure.Services;

public sealed class VersionService : IVersionService
{
    public Task<string> GetVersionAsync(CancellationToken cancellationToken = default)
    {
        string version = Assembly.GetEntryAssembly()?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion ?? "0.0.0-dev";

        return Task.FromResult(version);
    }
}
