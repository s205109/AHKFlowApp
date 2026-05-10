# CLI Authentication Design - Backlog 029

**Date:** 2026-05-10
**Backlog item:** `.claude/backlog/029-cli-authentication.md`
**Status:** Design reviewed; keep existing MSAL device-code approach

## Goal

Replace the CLI's temporary `AHKFLOW_TOKEN` authentication with first-class Entra ID sign-in using MSAL.NET device-code flow, persisted token cache, and `ahkflow login` / `ahkflow logout` commands.

## Review Decision

Keep the auth design from `docs/superpowers/specs/2026-05-08-cli-foundation-design.md`.

The design still matches the current code and Microsoft platform model:

- A CLI is a public client; device-code flow is the right non-browser sign-in UX.
- `AcquireTokenWithDeviceCode` stores successful results in MSAL's token cache, but does not check the cache first, so the provider must try `AcquireTokenSilent` before prompting.
- The existing one-app-registration model remains valid: the same app registration is both SPA client and API resource, with the CLI added as another public-client surface for the same `api://{clientId}/access_as_user` scope.
- Microsoft Graph exposes both `publicClient.redirectUris` and `isFallbackPublicClient` on the application resource, so `scripts/setup-entra-app.ps1` can stay idempotent and patch the current app registration.

Small refinements for the current repository shape:

- Put auth commands under `src/Tools/AHKFlowApp.CLI/Commands/Auth/` to match the current command folder style.
- Keep `IAuthTokenProvider` as the stable interface used by `BearerTokenHandler`.
- Add a small `IDeviceCodePromptWriter` so the MSAL provider can display the device-code challenge without changing `IAuthTokenProvider`.
- `MsalDeviceCodeTokenProvider` receives `IDeviceCodePromptWriter` through primary-constructor DI, and `Program.cs` registers `ConsoleErrorDeviceCodePromptWriter` as the production implementation.
- Replace the production DI registration of `EnvVarAuthTokenProvider` with an MSAL provider. Tests can keep using `StubAuthTokenProvider`.
- Update current auth failure text from `Set AHKFLOW_TOKEN...` to `Run 'ahkflow login' first.`.
- Explicitly update `DownloadCommandRunner`'s existing `catch (ApiException ex) when (ex.StatusCode == 401)` block from `Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.` to `Authentication failed. Run 'ahkflow login'.`.
- Validate `ClientId` and `TenantId` lazily inside `GetTokenAsync` / `LoginAsync`, before MSAL construction, so placeholder GUIDs produce a clear CLI error without breaking `ahkflow --help`.
- Update `tests/AHKFlowApp.CLI.Tests/Infrastructure/StubAuthTokenProvider.cs` to use the new `Run 'ahkflow login' first.` message when simulating unauthenticated API calls.

## Scope

In scope:

- Add `ahkflow login`.
- Add `ahkflow logout`.
- Add MSAL public-client token provider with persistent cache.
- Add device-code prompt output to stderr.
- Use cached tokens for all existing CLI API calls through `BearerTokenHandler`.
- Update Entra setup script for public-client device-code support.
- Update auth documentation and backlog item 029.

Out of scope:

- Multiple accounts / account selection.
- `--force-prompt` login.
- Client credentials or service-principal auth.
- Per-user CLI config files.
- CLI release packaging, code signing, or installer work.

## User Commands

### `ahkflow login`

Behavior:

- Builds scope as `api://{ClientId}/access_as_user`.
- Tries silent token acquisition first.
- If silent succeeds, exits `0` and prints `Already signed in as <username>`.
- If silent fails with UI required, starts device-code flow.
- The device-code callback writes the verification URL and user code to stderr through `IDeviceCodePromptWriter`.
- On success, exits `0` and prints `Signed in as <username>`.

No `--force-prompt` flag. Switching accounts is `ahkflow logout` followed by `ahkflow login`.

### `ahkflow logout`

Behavior:

- Enumerates all cached accounts and removes them.
- Deletes the cache file on a best-effort basis. `FileNotFoundException`, `IOException`, and `UnauthorizedAccessException` during cache-file delete are swallowed so logout remains idempotent.
- Exits `0` and prints `Signed out`.
- Idempotent when there is no cached account.

## Token Provider

`IAuthTokenProvider` remains:

```csharp
public interface IAuthTokenProvider
{
    Task<string> GetTokenAsync(CancellationToken ct);
    Task<LoginResult> LoginAsync(CancellationToken ct);
    Task LogoutAsync(CancellationToken ct);
}

public sealed record LoginResult(string Username, bool WasAlreadySignedIn);
```

`MsalDeviceCodeTokenProvider` responsibilities:

- Build one `IPublicClientApplication` from `ClientId` and `TenantId`.
- Use authority `https://login.microsoftonline.com/{TenantId}`.
- Use redirect URI `http://localhost`.
- Register the user token cache through `Microsoft.Identity.Client.Extensions.Msal`.
- `GetTokenAsync` validates `ClientId` and `TenantId` lazily, uses the first cached account, and calls `AcquireTokenSilent`.
- `GetTokenAsync` throws `NotAuthenticatedException` with message `Run 'ahkflow login' first.` when there is no cached account.
- `GetTokenAsync` throws `NotAuthenticatedException` with message `Run 'ahkflow login' first.` when `AcquireTokenSilent` throws `MsalUiRequiredException`, including expired or revoked refresh-token cases.
- `LoginAsync` uses silent first, then `AcquireTokenWithDeviceCode`.
- `LoginAsync` populates `LoginResult.Username` from `AuthenticationResult.Account.Username` (UPN).
- `LogoutAsync` removes every cached account and deletes the cache file if present, swallowing cache-file delete failures listed above.

Single-account behavior is intentional. If multiple accounts somehow exist in the cache, the provider uses the first account for token acquisition and removes all accounts on logout.

`IDeviceCodePromptWriter` is intentionally narrow and is injected into `MsalDeviceCodeTokenProvider`:

```csharp
public sealed class MsalDeviceCodeTokenProvider(
    IOptions<CliOptions> options,
    IDeviceCodePromptWriter promptWriter) : IAuthTokenProvider
{
}

public interface IDeviceCodePromptWriter
{
    Task WriteAsync(DeviceCodePrompt prompt, CancellationToken ct);
}

public sealed record DeviceCodePrompt(string VerificationUrl, string UserCode, string Message);
```

`Program.cs` registers `IDeviceCodePromptWriter` as `ConsoleErrorDeviceCodePromptWriter`. The production writer writes to `Console.Error`. The command still owns final success and failure messages; the prompt writer only handles the transient MSAL device-code instruction.

## Cache

Cache file: `Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AHKFlowApp", "msal-cache.bin3")` on all platforms.

The implementation should use `Microsoft.Identity.Client.Extensions.Msal` storage helpers rather than custom encryption or locking.

## Configuration

The CLI already reads:

```json
{
  "ApiBaseUrl": "https://placeholder-prod.azurewebsites.net",
  "ClientId": "00000000-0000-0000-0000-000000000000",
  "TenantId": "00000000-0000-0000-0000-000000000000"
}
```

Environment variables continue to override with the `AHKFLOW_` prefix:

- `AHKFLOW_ApiBaseUrl`
- `AHKFLOW_ClientId`
- `AHKFLOW_TenantId`

`ClientId` and `TenantId` must be valid non-empty GUIDs and not `Guid.Empty`. Invalid values produce a concise command error instead of an MSAL stack trace.

Validation is lazy. `Program.cs` must not construct MSAL or fail the host during root-command build, so `ahkflow --help` continues to work with placeholder config. The provider validates config only when `GetTokenAsync`, `LoginAsync`, or `LogoutAsync` needs MSAL state.

## Entra Setup

Update `scripts/setup-entra-app.ps1` for the existing app registration:

- Ensure `publicClient.redirectUris` contains `http://localhost`.
- Ensure `isFallbackPublicClient` is `true`.
- Preserve existing SPA redirect URIs, identifier URI, `access_as_user` scope, and pre-authorized app entries.
- Use the existing `Invoke-GraphPatch` and `Wait-ForCondition` helpers.
- Keep the script idempotent when rerun for `dev`, `test`, or `prod`.

No separate CLI app registration is created.

## Error Handling

Authentication errors map to exit code `3`:

- No cached token: `Run 'ahkflow login' first.`
- Silent refresh requires interaction: `Run 'ahkflow login' first.`
- API returns `401`: `Authentication failed. Run 'ahkflow login'.`

Required existing-code change: update `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs` line 47's `ApiException` `401` catch message to `Authentication failed. Run 'ahkflow login'.`.

User/config errors map to exit code `2` when they are caused by command input. Unexpected MSAL, network, or server errors map to exit code `1`.

Invalid `ClientId` / `TenantId` configuration maps to exit code `1` with a concise message naming the bad key. It is not a command-argument error.

All diagnostic/error text goes to stderr. Success messages go to stdout.

## Tests

Automated tests should cover behavior that does not require a real tenant:

- `login` formats already-signed-in and newly-signed-in results from a fake `IAuthTokenProvider`.
- `login` maps auth failures and invalid auth configuration to the expected exit code and stderr text.
- `logout` calls `IAuthTokenProvider.LogoutAsync`, prints `Signed out`, and is idempotent from the command perspective.
- `DeviceCodePromptWriter` writes the verification URL and user code to stderr.
- `BearerTokenHandler` continues attaching cached bearer tokens.
- Existing download/hotstring tests continue to pass with `StubAuthTokenProvider`; the stub's unauthenticated path should throw `NotAuthenticatedException` with `Run 'ahkflow login' first.` so tests do not preserve the old `AHKFLOW_TOKEN` copy.
- `scripts/setup-entra-app.ps1` changes are structurally testable through script review and manual smoke; no tenant-backed automated test is required.

Manual smoke after implementation:

1. Run `.\scripts\setup-entra-app.ps1 -Environment dev`.
2. Set `AHKFLOW_ApiBaseUrl`, `AHKFLOW_ClientId`, and `AHKFLOW_TenantId` for the local CLI.
3. Run `dotnet run --project src/Tools/AHKFlowApp.CLI -- login`.
4. Complete the device-code sign-in.
5. Run an authenticated command such as `hotstring list`.
6. Run `dotnet run --project src/Tools/AHKFlowApp.CLI -- logout`.
7. Run the authenticated command again and confirm it asks for login.

## References

- Existing combined CLI design: `docs/superpowers/specs/2026-05-08-cli-foundation-design.md`
- Microsoft MSAL device-code flow docs: https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-acquire-token-device-code-flow
- MSAL.NET `AcquireTokenWithDeviceCode`: https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.ipublicclientapplication.acquiretokenwithdevicecode
- Microsoft Graph `application` resource: https://learn.microsoft.com/en-us/graph/api/resources/application
- Microsoft Graph `publicClientApplication` resource: https://learn.microsoft.com/en-us/graph/api/resources/publicclientapplication
