using AHKFlowApp.CLI.Exceptions;

namespace AHKFlowApp.CLI.Services;

public sealed class EnvVarAuthTokenProvider : IAuthTokenProvider
{
    private const string EnvVarName = "AHKFLOW_TOKEN";

    public Task<string> GetTokenAsync(CancellationToken ct)
    {
        string? token = Environment.GetEnvironmentVariable(EnvVarName);
        if (string.IsNullOrWhiteSpace(token))
        {
            throw new NotAuthenticatedException(
                $"Not signed in. Set {EnvVarName} environment variable to a bearer token.");
        }
        return Task.FromResult(token);
    }

    public Task<LoginResult> LoginAsync(CancellationToken ct) =>
        throw new NotImplementedException("Login is implemented in backlog item 029 (MSAL device-code flow).");

    public Task LogoutAsync(CancellationToken ct) =>
        throw new NotImplementedException("Logout is implemented in backlog item 029.");
}
