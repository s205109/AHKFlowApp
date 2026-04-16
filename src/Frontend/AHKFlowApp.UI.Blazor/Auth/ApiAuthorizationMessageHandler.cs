using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.WebAssembly.Authentication;

namespace AHKFlowApp.UI.Blazor.Auth;

internal sealed class ApiAuthorizationMessageHandler : AuthorizationMessageHandler
{
    public ApiAuthorizationMessageHandler(
        IAccessTokenProvider provider,
        NavigationManager navigationManager,
        IConfiguration configuration)
        : base(provider, navigationManager)
    {
        ConfigureHandler(
            authorizedUrls: [configuration["ApiHttpClient:BaseAddress"]!],
            scopes: [configuration["AzureAd:DefaultScope"]!]);
    }
}
