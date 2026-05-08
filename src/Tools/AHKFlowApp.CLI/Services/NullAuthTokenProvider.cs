using AHKFlowApp.CLI.Exceptions;

namespace AHKFlowApp.CLI.Services;

public sealed class NullAuthTokenProvider : IAuthTokenProvider
{
    public Task<string> GetTokenAsync(CancellationToken ct) =>
        throw new NotAuthenticatedException("Not signed in. Run 'ahkflow login' first.");

    public Task<LoginResult> LoginAsync(CancellationToken ct) =>
        throw new NotImplementedException("Login is implemented in backlog item 029.");

    public Task LogoutAsync(CancellationToken ct) =>
        throw new NotImplementedException("Logout is implemented in backlog item 029.");
}
