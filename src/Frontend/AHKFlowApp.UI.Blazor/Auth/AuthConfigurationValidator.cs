namespace AHKFlowApp.UI.Blazor.Auth;

internal static class AuthConfigurationValidator
{
    public static void ValidateForMsal(IConfiguration configuration)
    {
        string[] requiredConfigKeys =
        [
            "ApiHttpClient:BaseAddress",
            "AzureAd:Authority",
            "AzureAd:ClientId",
            "AzureAd:DefaultScope"
        ];

        foreach (string key in requiredConfigKeys)
        {
            if (string.IsNullOrWhiteSpace(configuration[key]))
            {
                throw new InvalidOperationException($"Configuration value '{key}' is missing or empty.");
            }
        }

        string clientId = configuration["AzureAd:ClientId"]!;
        string authority = configuration["AzureAd:Authority"]!;
        if (clientId.Contains('<') || authority.Contains('<'))
        {
            throw new InvalidOperationException(
                "AzureAd configuration still contains placeholder values (e.g. '<your-client-id>'). " +
                "Run 'pwsh scripts/setup-dev-entra.ps1' from the repo root to create the dev Entra app " +
                "registration and populate wwwroot/appsettings.Development.json.");
        }
    }
}
