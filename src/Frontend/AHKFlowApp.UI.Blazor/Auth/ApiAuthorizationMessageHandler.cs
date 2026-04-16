using System.Net.Http.Headers;
using Microsoft.AspNetCore.Components.WebAssembly.Authentication;

namespace AHKFlowApp.UI.Blazor.Auth;

/// <summary>
/// Attaches a Bearer token to outgoing API requests when the user is authenticated.
/// Requests proceed unauthenticated when no token is available, allowing [AllowAnonymous]
/// endpoints (e.g. /health) to work without a login.
/// </summary>
internal sealed class ApiAuthorizationMessageHandler(
    IAccessTokenProvider tokenProvider,
    IConfiguration configuration) : DelegatingHandler
{
    private readonly string[] _scopes = [configuration["AzureAd:DefaultScope"]!];

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        AccessTokenResult tokenResult = await tokenProvider.RequestAccessToken(
            new AccessTokenRequestOptions { Scopes = _scopes });

        if (tokenResult.TryGetToken(out AccessToken? token))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Value);
        }

        return await base.SendAsync(request, cancellationToken);
    }
}
