namespace AHKFlowApp.CLI.Services;

public interface IAuthTokenProvider
{
    Task<string> GetTokenAsync(CancellationToken ct);
    Task<LoginResult> LoginAsync(CancellationToken ct);
    Task LogoutAsync(CancellationToken ct);
}

public sealed record LoginResult(string Username, bool WasAlreadySignedIn);
