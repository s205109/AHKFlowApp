namespace AHKFlowApp.UI.Blazor.Auth;

/// <summary>
/// Frontend MSAL settings derived from the consolidated <c>AzureAd</c> block
/// (<c>Instance</c> + <c>TenantId</c> + <c>ClientId</c>), shared in shape with the API.
/// </summary>
internal sealed record AzureAdSettings(string Authority, string ClientId, string Scope, bool ValidateAuthority)
{
    /// <summary>
    /// Resolves MSAL settings from configuration. Trusts that the required keys are present —
    /// <see cref="Startup.StartupConfigValidator"/> guards that at the boundary before this runs.
    /// </summary>
    public static AzureAdSettings Resolve(IConfiguration configuration)
    {
        string instance = configuration["AzureAd:Instance"]!.TrimEnd('/');
        string tenantId = configuration["AzureAd:TenantId"]!;
        string clientId = configuration["AzureAd:ClientId"]!;

        string authority = $"{instance}/{tenantId}";

        // Blank Scopes (e.g. a deploy variable that resolved to empty) must NOT win over the
        // derived default — an empty default-access-token scope would silently break MSAL.
        string? configuredScope = configuration["AzureAd:Scopes"];
        string scope = string.IsNullOrWhiteSpace(configuredScope)
            ? $"api://{clientId}/access_as_user"
            : configuredScope;

        bool validateAuthority = configuration.GetValue("AzureAd:ValidateAuthority", true);

        return new AzureAdSettings(authority, clientId, scope, validateAuthority);
    }
}
