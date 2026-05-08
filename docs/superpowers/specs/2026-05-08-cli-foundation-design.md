# CLI Foundation Design — 017 + 029 + 028

**Date:** 2026-05-08
**Backlog items:** 017 (scaffold CLI), 029 (CLI authentication), 028 (CLI download command)
**Status:** Design — ready for implementation planning

## Goal

Stand up the `ahkflow` CLI from zero to a working `download` command. Three backlog items planned together because 028 is unusable without 017 (project scaffold) and 029 (auth); designing them in isolation would defer real decisions about shared concerns (HttpClient, DI, config, token cache).

## Scope

In scope:
- New `src/Tools/AHKFlowApp.CLI` console project (.NET 10).
- New `tests/AHKFlowApp.CLI.Tests` xUnit project.
- Three commands: `login`, `logout`, `download`.
- MSAL device-code authentication against the existing Entra app registration.
- One-line update to `scripts/setup-entra-app.ps1` to add the public-client redirect URI.
- CLI included in existing `ci.yml` build/test (no new workflow).
- Update `.claude/CLAUDE.md` to remove "CLI application" from out-of-scope.

Out of scope (future backlog):
- Single-file publish, code signing, release workflow (`release-cli.yml`).
- Hotstring/Hotkey CRUD via CLI (was item 018; not picked up here).
- Multi-environment config switching (one shipped binary points at PROD; env vars override).
- A `config` subcommand or per-user JSON config file.
- Process-level CLI tests that spawn the built binary (covered by `--help` smoke step in CI).

## Architecture

### Project layout

```
src/Tools/AHKFlowApp.CLI/
  AHKFlowApp.CLI.csproj
  Program.cs                          # Host builder, DI, System.CommandLine root
  appsettings.json                    # ApiBaseUrl, ClientId, TenantId — PROD defaults
  Commands/
    LoginCommand.cs
    LogoutCommand.cs
    DownloadCommand.cs
  Services/
    IAuthTokenProvider.cs             # GetTokenAsync, LoginAsync, LogoutAsync
    NullAuthTokenProvider.cs          # 017 stub; replaced in 029
    MsalDeviceCodeTokenProvider.cs    # 029
    BearerTokenHandler.cs             # DelegatingHandler — Authorization header
    IDownloadsApiClient.cs
    DownloadsApiClient.cs
    IProfilesApiClient.cs             # ListAsync only — for name → id resolution
    ProfilesApiClient.cs
  Auth/
    MsalCacheConfig.cs                # cache file path + DPAPI/Keychain wiring
  Exceptions/
    NotAuthenticatedException.cs

tests/AHKFlowApp.CLI.Tests/
  AHKFlowApp.CLI.Tests.csproj
  CliTestFixture.cs                   # WebApplicationFactory<Program> + Testcontainers SQL
  Commands/
    DownloadCommandTests.cs           # arg parsing (unit) + end-to-end (integration)
  Services/
    BearerTokenHandlerTests.cs
    ProfileResolutionTests.cs
```

Single console project — no separate Core library. Surface is small enough that splitting would add more boilerplate than testability.

### Packages

| Package | Purpose |
|---|---|
| `System.CommandLine` | Argument parsing, help, exit codes |
| `Microsoft.Extensions.Hosting` | Host builder, DI, config, logging |
| `Microsoft.Identity.Client` | MSAL.NET — device-code flow |
| `Microsoft.Identity.Client.Extensions.Msal` | Cross-platform persisted token cache |
| `Microsoft.Extensions.Http.Resilience` | `.AddStandardResilienceHandler()` (per AGENTS.md) |
| `Serilog.Extensions.Hosting` + sinks | Structured logging to stderr |

Versions resolved via `dotnet add package` (no hardcoded versions; CPM via `Directory.Packages.props`).

### HttpClient pipeline

```
DownloadsApiClient
  → HttpClient (named "ahkflow-api")
      → BearerTokenHandler (calls IAuthTokenProvider.GetTokenAsync)
      → StandardResilienceHandler
      → SocketsHttpHandler
```

Registered via `IHttpClientFactory.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(...)` in `Program.cs`. Same shape for `IProfilesApiClient`.

## Command surface

Binary name: **`ahkflow`** (assembly `AHKFlowApp.CLI`, output name `ahkflow`).

### `ahkflow login`

- Triggers MSAL device-code flow against scope `api://{ClientId}/access_as_user`.
- Tries silent token acquisition first; if cache hit, prints `Already signed in as <upn>` and exits 0.
- Otherwise prints to **stderr**: `To sign in, open https://microsoft.com/devicelogin and enter code XXXXX`.
- On success: writes token to MSAL cache, prints `Signed in as <upn>` to stdout, exits 0.
- No `--force-prompt` flag — `logout` then `login` is the documented re-auth path.

### `ahkflow logout`

- Enumerates accounts in MSAL cache, removes each, deletes cache file.
- Prints `Signed out`, exits 0.
- Idempotent — exits 0 even if nothing was cached.

### `ahkflow download`

| Option | Required | Notes |
|---|---|---|
| `--profile <name>` | Either `--profile` OR `--all` | Resolves to profileId via `GET /api/v1/profiles`. Case-insensitive match (matches SQL CI collation). |
| `--all` | Either `--profile` OR `--all` | Hits `/api/v1/downloads/zip`. |
| `-o, --output <path>` | No | File path, or `-` for stdout. |
| `--force` | No | Overwrite existing output file. |

Default output paths when `-o` omitted:
- `--profile Work` → `./ahkflow_Work.ahk` (uses Content-Disposition filename from server, which is already sanitized per backlog 027).
- `--all` → `./ahkflow_scripts.zip`.

`-o -` (stdout) is **supported with `--all`** — the raw zip bytes are written to stdout for piping (e.g., `ahkflow download --all -o - | tar -xf-` on macOS/Linux, or piping into PowerShell's `[System.IO.Compression.ZipArchive]`). Combined with the Serilog-to-stderr wiring above, stdout stays clean.

Mutually exclusive: `--profile` and `--all`. Specifying both, or neither, → exit 2 with error.

Profile not found: exit 2 with `Profile 'X' not found. Available: A, B, C` to stderr.

Output collision (file exists, no `--force`): exit 2 with `File 'foo.ahk' exists. Use --force to overwrite.` to stderr; file untouched.

Not signed in (silent refresh fails): exit 3 with `Run 'ahkflow login' first.` to stderr.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Unexpected error (network, server 5xx, server 403) |
| 2 | User error (bad args, profile not found, file exists without --force) |
| 3 | Not authenticated (no cached token, silent refresh failed, server 401) |

**HTTP status mapping:**
- `401 Unauthorized` from the API → exit 3 with `Authentication failed. Run 'ahkflow login'.` (token rejected, e.g., expired between cache check and request).
- `403 Forbidden` from the API → exit 1 with the server's ProblemDetails `detail` field (auth ok but the principal lacks scope/permission — not something `login` will fix).
- `404 Not Found` on `/downloads/{id}` → exit 2 with `Profile 'X' not found.` (matches the local resolution path).
- `5xx` → exit 1 after resilience handler retries are exhausted.

### Logging

- Default: quiet — only the result line goes to stdout.
- `--verbose`: Information-level Serilog to stderr.
- Errors: always to stderr.
- The CLI never writes its own logs to disk; `appsettings.json` Serilog config has no file sink.

**Serilog stderr wiring (non-default — `WriteTo.Console()` writes to stdout by default):**
```csharp
.WriteTo.Console(standardErrorFromLevel: LogEventLevel.Verbose)
```
This forces every log event (including Information from `--verbose`) to stderr, leaving stdout clean for command output. Critical because `download -o -` writes raw script bytes to stdout — any Serilog event landing on stdout would corrupt the output.

**Test:** unit test that runs `download -o -` against the test fixture with `--verbose` and asserts:
- stdout contains exactly the script bytes (no log lines mixed in).
- stderr contains the expected log lines.

## Authentication

### 017 stub

`IAuthTokenProvider` interface plus `NullAuthTokenProvider` that throws `NotAuthenticatedException` on every call. Lets `download` compile and be partially testable before 029 lands.

```csharp
public interface IAuthTokenProvider
{
    Task<string> GetTokenAsync(CancellationToken ct);
    Task<LoginResult> LoginAsync(CancellationToken ct);
    Task LogoutAsync(CancellationToken ct);
}

public sealed record LoginResult(string Username, bool WasAlreadySignedIn);
```

`LoginCommand` formats the result: `WasAlreadySignedIn=true` → `Already signed in as {Username}`; `false` → `Signed in as {Username}`. The provider does not write to console — the command owns I/O.

**Multi-account behavior:** the cache is treated as single-account. `GetTokenAsync` and `LoginAsync` use `accounts.FirstOrDefault()` after `pca.GetAccountsAsync()`. `LogoutAsync` removes **all** cached accounts (clean slate). If the user wants to switch identity, `logout` then `login` is the documented path. We do not persist a "selected account id" — adding multi-account support is a future backlog item.

### 029 implementation

`MsalDeviceCodeTokenProvider`:

- One `IPublicClientApplication` built in DI:
  - `ClientId`, `TenantId` from config.
  - `RedirectUri = http://localhost`.
  - Cache wired via `MsalCacheHelper` from `Microsoft.Identity.Client.Extensions.Msal`.

- Cache storage:
  - File: `%LOCALAPPDATA%\AHKFlowApp\msal-cache.bin3` (Windows) / XDG-conformant path elsewhere.
  - Encryption: DPAPI (Windows), Keychain (macOS), libsecret with file fallback (Linux) — provided by the extensions package.
  - `MsalCacheHelper.RegisterCache(pca.UserTokenCache)` handles all the locking.

- `GetTokenAsync()`:
  1. `AcquireTokenSilent(scopes, account).ExecuteAsync()` using cached refresh token.
  2. On `MsalUiRequiredException` → throw `NotAuthenticatedException` (caller maps to exit 3).

- `LoginAsync()`:
  1. Try silent first; if it works, return existing account (no prompt).
  2. Else `AcquireTokenWithDeviceCode(scopes, callback).ExecuteAsync()`; callback prints device code to stderr.

- `LogoutAsync()`:
  1. `pca.GetAccountsAsync()` → for each, `pca.RemoveAsync(account)`.
  2. Delete the cache file (best-effort; ignore `FileNotFoundException`).

### Entra registration changes

Three Graph manifest changes on the existing app registration (no new app, no new scope — same `access_as_user`):

1. **Add public-client redirect URI** — `publicClient.redirectUris` must include `http://localhost`. This is a separate collection from `spa.redirectUris` (which the script already manages); the new collection has to be PATCHed in:
   ```json
   { "publicClient": { "redirectUris": ["http://localhost"] } }
   ```

2. **Enable public-client flows** — set `isFallbackPublicClient: true` on the application object. Without this, MSAL's device-code flow fails with `AADSTS7000218` ("client_assertion or client_secret required"). PATCH:
   ```json
   { "isFallbackPublicClient": true }
   ```

3. **`scripts/setup-entra-app.ps1` updates:**
   - After the existing SPA-redirect block (around line 142), add a `publicClient.redirectUris` PATCH with the same `Wait-ForCondition` pattern.
   - Add an `isFallbackPublicClient: true` PATCH on the application root.
   - Both must be idempotent — read current state first, only PATCH if needed (the script's existing pattern).

These are all PATCHes via `Invoke-GraphPatch`. No `az ad app update` flag exists for `isFallbackPublicClient` — Graph PATCH is required.

## Configuration

CLI reads config in this order (later overrides earlier):

1. `appsettings.json` next to the binary — PROD defaults shipped with the CLI:
   ```json
   {
     "ApiBaseUrl": "https://<prod-app-service>.azurewebsites.net",
     "ClientId": "<prod-client-id>",
     "TenantId": "<prod-tenant-id>"
   }
   ```
2. Environment variables (override at runtime for dev/test). With `AddEnvironmentVariables("AHKFLOW_")` the prefix is stripped to produce the config key, so the env var names must match the JSON keys exactly:
   - `AHKFLOW_ApiBaseUrl`
   - `AHKFLOW_ClientId`
   - `AHKFLOW_TenantId`

Standard `IConfigurationBuilder` chain (`AddJsonFile` + `AddEnvironmentVariables("AHKFLOW_")`). On case-insensitive shells (Windows `cmd`/PowerShell) casing doesn't matter; on Linux/macOS the variable name is case-sensitive but the resulting config key resolves case-insensitively in .NET configuration. No CLI flags for these — keeps every command invocation clean.

No per-user config file. No `ahkflow config` command.

## Testing strategy

| Layer | Type | Approach |
|---|---|---|
| `DownloadCommand` arg parsing | Unit | Invoke `System.CommandLine` parser directly; assert exit code + stderr. No I/O, no DI. |
| `BearerTokenHandler` | Unit | NSubstitute the inner handler + `IAuthTokenProvider`; assert `Authorization: Bearer <token>` is attached. |
| Profile name → id resolution | Unit | Stub `IProfilesApiClient`; assert correct id flows to downloads client; assert error path when name missing. |
| End-to-end download (happy path, per-profile) | Integration | Reuse the API's `WebApplicationFactory<Program>` + `WithTestAuth(builder)` extension already used in `AHKFlowApp.API.Tests` (configures a stub auth scheme via builder — oid, email, scope). CLI's `HttpClient` is pointed at `factory.Server.CreateClient()`. Testcontainers SQL via `SqlContainerFixture`. Assert bytes + filename. |
| `--all` zip download | Integration | Same harness; assert zip entry count + names + per-entry content. |
| `--all -o -` (zip to stdout) | Integration | Capture stdout as bytes; assert it's a valid zip with correct entries; assert no log lines on stdout when `--verbose` is set. |
| `download -o - --verbose` (stdout/stderr split) | Integration | Assert stdout contains exactly the script bytes and stderr contains the verbose log lines. Guards against the default `WriteTo.Console()` pitfall. |
| Server 401 → exit 3 | Integration | Configure test handler to reject the token; assert exit 3 + "Authentication failed. Run 'ahkflow login'." |
| Server 403 → exit 1 | Integration | Configure test handler to authenticate but fail scope check; assert exit 1 + ProblemDetails.detail. |
| Not signed in | Integration | Harness with `NullAuthTokenProvider`; assert exit 3 + stderr. |
| Profile not found | Integration | Seed two profiles; request a third; assert exit 2 + "Available: ..." list. |
| Output collision (no `--force`) | Integration | Pre-create output file in `Path.GetTempPath()`; assert exit 2, file untouched. |
| `--force` overwrite | Integration | Same but with `--force`; assert file replaced. |
| `MsalDeviceCodeTokenProvider` | **Skip** | Wraps `IPublicClientApplication` — don't mock what we own; third-party surface too thin to mock meaningfully. |
| Login/logout flow | **Skip** | Device-code can't be exercised without a real tenant. Manual smoke test in 029's PR description. |

Shared fixture: `CliTestFixture` as `IClassFixture<>` (or `ICollectionFixture<>` if container startup proves noisy across classes).

Test auth: reuse `WithTestAuth(builder)` from `AHKFlowApp.API.Tests`. CLI's `IAuthTokenProvider` is replaced with a fake returning any non-empty string — the test auth scheme on the factory side ignores the actual token value and authenticates based on the builder configuration.

## CI/CD

- `ci.yml` already runs `dotnet build` and `dotnet test` on the whole solution — new CLI project + test project picked up automatically.
- Add one smoke step after build:
  ```yaml
  - name: CLI --help smoke
    run: dotnet run --project src/Tools/AHKFlowApp.CLI -- --help
  ```
  Catches DI registration errors that wouldn't surface in unit tests.

No deploy workflow yet. CLI distribution (single-file publish, signing, releases) is a future backlog item.

## Implementation order

Each backlog item is one PR. Sequence avoids stub-commits-then-real-commits rebases.

1. **017 — Scaffold** (PR #1)
   - New project, `Program.cs` + DI + System.CommandLine, `appsettings.json`, `--help` works.
   - `IAuthTokenProvider` exists with `NullAuthTokenProvider`.
   - `BearerTokenHandler`, `IDownloadsApiClient` interface (no impl yet).
   - **Add new projects to `AHKFlowApp.slnx`:** `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` under a new `/src/Tools/` folder; `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj` under `/tests/`. Without this CI's root-level `dotnet build` won't pick the projects up.
   - CI smoke step added.
   - Update `.claude/CLAUDE.md` to remove "CLI application" from out-of-scope.

2. **029 — Authentication** (PR #2)
   - Replace `NullAuthTokenProvider` with `MsalDeviceCodeTokenProvider`.
   - Add `LoginCommand` + `LogoutCommand`.
   - MSAL cache wiring.
   - Update `scripts/setup-entra-app.ps1` for public-client redirect URI.
   - Update `docs/architecture/authentication.md` "CLI authentication" section.

3. **028 — Download** (PR #3)
   - `DownloadCommand` (per-profile + `--all`).
   - `DownloadsApiClient` impl, `ProfilesApiClient` impl (ListAsync).
   - `--output`, `--force`, profile name resolution.
   - Integration tests.

## Decisions locked in

- Binary name: `ahkflow` (not `ahkflowapp`). **Backlog AC change:** item 028 originally specified `ahkflowapp download ahk --profile <name>`. This spec replaces it with `ahkflow download --profile <name>` (shorter binary, no `ahk` sub-noun since the only artifact is `.ahk`). The backlog item must be updated when 028 is implemented to reflect the new AC text.
- Single project, no separate Core library.
- `System.CommandLine` (not Spectre.Console.Cli).
- `Microsoft.Extensions.Hosting` for DI/config/logging.
- File output is default; `-o -` for stdout.
- `--force` required to overwrite existing files.
- Case-insensitive profile name matching.
- Device-code flow only (no interactive browser flow, no client-credentials).
- Shipped `appsettings.json` + `AHKFLOW_*` env-var overrides; no per-user config.
- 017/029/028 ship as separate PRs.

## Out of scope (deferred)

- Single-file publish, code signing, GitHub Releases, `release-cli.yml`.
- Hotstring/Hotkey CRUD via CLI.
- `config` subcommand / per-user config file.
- Multi-environment config profile switching beyond env vars.
- Process-level tests spawning the built binary.
- `--force-prompt` / re-auth flag on `login`.

## Dependencies

- Backlog 003 (solution scaffold) — done.
- Backlog 012 (UI/API auth) — done; CLI reuses the same Entra app + scope.
- Backlog 027 (download endpoint) — done; CLI calls these endpoints unchanged.

## Risks

- **MSAL cache portability:** DPAPI cache is per-user on Windows. Acceptable — matches user expectations for a personal CLI.
- **Testcontainers SQL on Windows CI runners:** already proven by other test projects in this repo.
- **Device-code flow UX:** stderr printout requires a TTY. CI/non-interactive environments must use a pre-cached token (set up via interactive `login` once on the dev machine).
