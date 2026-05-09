using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;

namespace AHKFlowApp.CLI.Tests.Infrastructure;

internal sealed class StubAuthTokenProvider(string? token) : IAuthTokenProvider
{
    public Task<string> GetTokenAsync(CancellationToken ct) =>
        token is null
            ? throw new NotAuthenticatedException(
                "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.")
            : Task.FromResult(token);

    public Task<LoginResult> LoginAsync(CancellationToken ct) => throw new NotImplementedException();
    public Task LogoutAsync(CancellationToken ct) => throw new NotImplementedException();
}
