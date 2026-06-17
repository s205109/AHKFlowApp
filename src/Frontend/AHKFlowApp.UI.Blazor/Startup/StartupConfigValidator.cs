namespace AHKFlowApp.UI.Blazor.Startup;

/// <summary>
/// Boundary check for the frontend's required startup configuration. Returns a
/// <see cref="StartupErrorReason"/> describing the problem instead of throwing, so
/// Program.cs can boot a friendly error page rather than crashing into a blank screen.
/// </summary>
internal static class StartupConfigValidator
{
    private static readonly string[] RequiredKeys =
    [
        "ApiHttpClient:BaseAddress",
        "AzureAd:Instance",
        "AzureAd:TenantId",
        "AzureAd:ClientId"
    ];

    /// <summary>
    /// Returns <c>null</c> when configuration is usable, otherwise the reason it is not.
    /// </summary>
    public static StartupErrorReason? Check(IConfiguration configuration)
    {
        if (RequiredKeys.Any(key => string.IsNullOrWhiteSpace(configuration[key])))
        {
            return StartupErrorReason.MissingFrontendConfig;
        }

        if (RequiredKeys.Any(key => configuration[key]!.Contains('<')))
        {
            return StartupErrorReason.PlaceholderConfig;
        }

        return null;
    }
}
