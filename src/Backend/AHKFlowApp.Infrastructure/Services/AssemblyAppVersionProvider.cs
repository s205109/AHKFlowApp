using System.Reflection;
using AHKFlowApp.Application.Abstractions;

namespace AHKFlowApp.Infrastructure.Services;

public sealed class AssemblyAppVersionProvider : IAppVersionProvider
{
    private static readonly string s_version = ResolveVersion(Assembly.GetEntryAssembly());

    public string GetVersion() => s_version;

    internal static string ResolveVersion(Assembly? entry)
    {
        string? info = entry?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        if (!string.IsNullOrWhiteSpace(info))
        {
            int plus = info.IndexOf('+');
            return plus >= 0 ? info[..plus] : info;
        }

        return entry?.GetName().Version?.ToString() ?? "0.0.0-dev";
    }
}
