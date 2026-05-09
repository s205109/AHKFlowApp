# CLI Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `ahkflow` CLI from zero to a working `download` command across three sequential PRs (backlog 017 + 029 + 028).

**Architecture:** Single .NET 10 console project (`src/Tools/AHKFlowApp.CLI`) using `Microsoft.Extensions.Hosting` for DI/config/logging and `System.CommandLine` for argument parsing. Auth via `Microsoft.Identity.Client` device-code flow with persisted token cache. HttpClient pipeline: `IHttpClientFactory` → `BearerTokenHandler` (DelegatingHandler) → `StandardResilienceHandler`. Test project reuses `AHKFlowApp.TestUtilities` (`CustomWebApplicationFactory`, `TestAuthHandler`, `SqlContainerFixture`, `WithTestAuth(builder)`).

**Tech Stack:** .NET 10, System.CommandLine, Microsoft.Extensions.Hosting, Microsoft.Identity.Client, Microsoft.Identity.Client.Extensions.Msal, Serilog, xUnit, FluentAssertions, NSubstitute, Testcontainers (transitively via TestUtilities).

**Spec:** `docs/superpowers/specs/2026-05-08-cli-foundation-design.md`

**Branch:** `feature/017-cli-foundation` (already created; spec already committed). Phase 1 will commit on this branch and open PR #1. Phase 2 starts a new branch from `main` after PR #1 merges. Phase 3 starts a new branch from `main` after PR #2 merges.

---

## File structure (locked in by this plan)

**New files in `src/Tools/AHKFlowApp.CLI/`:**

| Path | Responsibility |
|---|---|
| `AHKFlowApp.CLI.csproj` | Console exe project, output name `ahkflow`, .NET 10 |
| `Program.cs` | Host builder, Serilog config, DI registration, root command dispatch |
| `appsettings.json` | `ApiBaseUrl`, `ClientId`, `TenantId` (PROD defaults) |
| `CliOptions.cs` | Strongly typed config record |
| `Commands/RootCli.cs` | Builds the System.CommandLine root with subcommands |
| `Commands/LoginCommand.cs` | `ahkflow login` (Phase 2) |
| `Commands/LogoutCommand.cs` | `ahkflow logout` (Phase 2) |
| `Commands/DownloadCommand.cs` | `ahkflow download` (Phase 3) |
| `Services/IAuthTokenProvider.cs` | Interface + `LoginResult` record + `NotAuthenticatedException` |
| `Services/NullAuthTokenProvider.cs` | Phase 1 stub — throws on every call |
| `Services/MsalDeviceCodeTokenProvider.cs` | Phase 2 — real MSAL impl |
| `Services/BearerTokenHandler.cs` | DelegatingHandler — attaches `Authorization: Bearer <token>` |
| `Services/IDownloadsApiClient.cs` | `GetProfileScriptAsync`, `GetAllProfileScriptsZipAsync` |
| `Services/DownloadsApiClient.cs` | Phase 3 impl |
| `Services/IProfilesApiClient.cs` | `ListAsync` only |
| `Services/ProfilesApiClient.cs` | Phase 3 impl |
| `Services/CliFile.cs` | Static helpers: `ResolveOutputPath`, `WriteWithCollisionCheck` |
| `Auth/MsalCacheConfig.cs` | Phase 2 — cache file path + storage properties |

**New files in `tests/AHKFlowApp.CLI.Tests/`:**

| Path | Responsibility |
|---|---|
| `AHKFlowApp.CLI.Tests.csproj` | xUnit project |
| `CliRunner.cs` | In-process invocation helper — builds host with overrides, invokes root, captures stdout/stderr/exit |
| `Commands/DownloadCommandTests.cs` | All download integration tests (Phase 3) |
| `Services/BearerTokenHandlerTests.cs` | Header attachment unit tests (Phase 1) |
| `Collections.cs` | xUnit `[CollectionDefinition("WebApi")]` paired with `SqlContainerFixture` (Phase 3) |

**Modified files (cumulative across phases):**

- `AHKFlowApp.slnx` — add CLI + test project entries (Phase 1)
- `Directory.Packages.props` — add System.CommandLine, MSAL, hosting packages (Phases 1 & 2)
- `.github/workflows/ci.yml` — add CLI `--help` smoke step (Phase 1)
- `.claude/CLAUDE.md` — remove "CLI application" from Out of Scope (Phase 1)
- `scripts/setup-entra-app.ps1` — public-client redirect URI + isFallbackPublicClient (Phase 2)
- `docs/architecture/authentication.md` — replace "Deferred to backlog item 029" section (Phase 2)
- `.claude/backlog/017-scaffold-cli-project.md` — mark complete (end of Phase 1)
- `.claude/backlog/029-cli-authentication.md` — mark complete (end of Phase 2)
- `.claude/backlog/028-cli-download-command.md` — update AC text (`ahkflow download --profile`) and mark complete (end of Phase 3)

---

# Phase 1 — Backlog 017: Scaffold (PR #1)

Branch: `feature/017-cli-foundation` (already exists with spec commit).

### Task 1: Create CLI project and add to solution

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`
- Create: `src/Tools/AHKFlowApp.CLI/Program.cs` (placeholder)
- Modify: `AHKFlowApp.slnx`

- [ ] **Step 1: Create `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>ahkflow</AssemblyName>
    <RootNamespace>AHKFlowApp.CLI</RootNamespace>
    <InvariantGlobalization>false</InvariantGlobalization>
  </PropertyGroup>

</Project>
```

- [ ] **Step 2: Create `src/Tools/AHKFlowApp.CLI/Program.cs` placeholder**

```csharp
Console.WriteLine("ahkflow CLI (scaffold)");
return 0;
```

- [ ] **Step 3: Add the project to `AHKFlowApp.slnx`**

Modify the file. Add a new `/src/Tools/` folder after the existing `/src/Frontend/` folder block, inside `<Solution>`:

```xml
  <Folder Name="/src/Tools/">
    <Project Path="src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj" />
  </Folder>
```

- [ ] **Step 4: Verify solution builds**

Run: `dotnet build --configuration Release`
Expected: succeeds, includes the new `AHKFlowApp.CLI` project in the build output.

- [ ] **Step 5: Verify the binary name and run it**

Run: `dotnet run --project src/Tools/AHKFlowApp.CLI`
Expected: prints `ahkflow CLI (scaffold)` and exits 0.

- [ ] **Step 6: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI AHKFlowApp.slnx
git commit -m "feat(017): scaffold AHKFlowApp.CLI console project"
```

---

### Task 2: Add packages and CliOptions

**Files:**
- Modify: `Directory.Packages.props`
- Modify: `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`
- Create: `src/Tools/AHKFlowApp.CLI/CliOptions.cs`
- Create: `src/Tools/AHKFlowApp.CLI/appsettings.json`

- [ ] **Step 1: Add package versions to `Directory.Packages.props`**

Run from solution root, one at a time, to add packages with current stable versions:

```bash
dotnet add src/Tools/AHKFlowApp.CLI package Microsoft.Extensions.Hosting
dotnet add src/Tools/AHKFlowApp.CLI package System.CommandLine --prerelease
dotnet add src/Tools/AHKFlowApp.CLI package Microsoft.Extensions.Http.Resilience
dotnet add src/Tools/AHKFlowApp.CLI package Serilog.Extensions.Hosting
dotnet add src/Tools/AHKFlowApp.CLI package Serilog.Sinks.Console
dotnet add src/Tools/AHKFlowApp.CLI package Serilog.Settings.Configuration
```

`System.CommandLine` is still in beta (2.x) so `--prerelease` is required. Each command writes the version into `Directory.Packages.props` (CPM enabled) and the unversioned `<PackageReference>` into the csproj.

- [ ] **Step 2: Verify the csproj has unversioned references**

Open `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` and confirm an `<ItemGroup>` with entries like:

```xml
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" />
    <PackageReference Include="System.CommandLine" />
    <PackageReference Include="Microsoft.Extensions.Http.Resilience" />
    <PackageReference Include="Serilog.Extensions.Hosting" />
    <PackageReference Include="Serilog.Sinks.Console" />
    <PackageReference Include="Serilog.Settings.Configuration" />
  </ItemGroup>
```

If `dotnet add package` wrote any `Version="..."` attributes into the csproj, remove them — CPM forbids per-csproj versions.

- [ ] **Step 3: Create `src/Tools/AHKFlowApp.CLI/CliOptions.cs`**

```csharp
namespace AHKFlowApp.CLI;

public sealed record CliOptions
{
    public string ApiBaseUrl { get; init; } = "";
    public string ClientId { get; init; } = "";
    public string TenantId { get; init; } = "";
}
```

- [ ] **Step 4: Create `src/Tools/AHKFlowApp.CLI/appsettings.json`**

```json
{
  "ApiBaseUrl": "https://placeholder-prod.azurewebsites.net",
  "ClientId": "00000000-0000-0000-0000-000000000000",
  "TenantId": "00000000-0000-0000-0000-000000000000"
}
```

The placeholder values get overridden via `AHKFLOW_*` env vars in CI/dev. Real PROD values are filled in by deployment tooling — out of scope for this PR.

- [ ] **Step 5: Mark `appsettings.json` to copy to output**

Modify `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` — add inside the `<Project>` element after the existing `<ItemGroup>`:

```xml
  <ItemGroup>
    <None Update="appsettings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>
```

- [ ] **Step 6: Build and commit**

```bash
dotnet build --configuration Release
git add Directory.Packages.props src/Tools/AHKFlowApp.CLI
git commit -m "feat(017): add CLI packages and config schema"
```

Expected: build succeeds.

---

### Task 3: Auth interface, stub, BearerTokenHandler, exception

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/IAuthTokenProvider.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/NullAuthTokenProvider.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/BearerTokenHandler.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Exceptions/NotAuthenticatedException.cs`

- [ ] **Step 1: Create `Exceptions/NotAuthenticatedException.cs`**

```csharp
namespace AHKFlowApp.CLI.Exceptions;

public sealed class NotAuthenticatedException(string message) : Exception(message);
```

- [ ] **Step 2: Create `Services/IAuthTokenProvider.cs`**

```csharp
namespace AHKFlowApp.CLI.Services;

public interface IAuthTokenProvider
{
    Task<string> GetTokenAsync(CancellationToken ct);
    Task<LoginResult> LoginAsync(CancellationToken ct);
    Task LogoutAsync(CancellationToken ct);
}

public sealed record LoginResult(string Username, bool WasAlreadySignedIn);
```

- [ ] **Step 3: Create `Services/NullAuthTokenProvider.cs`**

```csharp
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
```

- [ ] **Step 4: Create `Services/BearerTokenHandler.cs`**

```csharp
using System.Net.Http.Headers;

namespace AHKFlowApp.CLI.Services;

public sealed class BearerTokenHandler(IAuthTokenProvider tokenProvider) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        string token = await tokenProvider.GetTokenAsync(cancellationToken);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await base.SendAsync(request, cancellationToken);
    }
}
```

- [ ] **Step 5: Build and commit**

```bash
dotnet build --configuration Release
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(017): add IAuthTokenProvider stub and BearerTokenHandler"
```

Expected: build succeeds.

---

### Task 4: API client interfaces (no impls yet)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/IDownloadsApiClient.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/IProfilesApiClient.cs`

- [ ] **Step 1: Create `Services/IDownloadsApiClient.cs`**

```csharp
namespace AHKFlowApp.CLI.Services;

public interface IDownloadsApiClient
{
    Task<DownloadResult> GetProfileScriptAsync(Guid profileId, CancellationToken ct);
    Task<DownloadResult> GetAllProfileScriptsZipAsync(CancellationToken ct);
}

public sealed record DownloadResult(byte[] Bytes, string FileName, string ContentType);
```

- [ ] **Step 2: Create `Services/IProfilesApiClient.cs`**

```csharp
namespace AHKFlowApp.CLI.Services;

public interface IProfilesApiClient
{
    Task<IReadOnlyList<ProfileSummary>> ListAsync(CancellationToken ct);
}

public sealed record ProfileSummary(Guid Id, string Name);
```

- [ ] **Step 3: Build and commit**

```bash
dotnet build --configuration Release
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(017): add API client interfaces"
```

Expected: build succeeds.

---

### Task 5: Program.cs — host, DI, Serilog, root command

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`

- [ ] **Step 1: Create `Commands/RootCli.cs`**

```csharp
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands;

public static class RootCli
{
    public static readonly Option<bool> VerboseOption = new("--verbose", "-v")
    {
        Description = "Enable Information-level logs to stderr.",
        Recursive = true,
    };

    public static RootCommand Build(IServiceProvider services)
    {
        RootCommand root = new("ahkflow - AHKFlowApp CLI")
        {
            VerboseOption,
        };
        // Subcommands wired in subsequent phases:
        //   root.Subcommands.Add(LoginCommand.Build(services));
        //   root.Subcommands.Add(LogoutCommand.Build(services));
        //   root.Subcommands.Add(DownloadCommand.Build(services));
        return root;
    }
}
```

`Recursive = true` makes the option available on every subcommand without redeclaring it. Program.cs pre-parses `args` for `--verbose`/`-v` to set the Serilog minimum level before the host is built.

- [ ] **Step 2: Replace `Program.cs` contents**

```csharp
using AHKFlowApp.CLI;
using AHKFlowApp.CLI.Commands;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;
using System.CommandLine;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);

builder.Configuration
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: false)
    .AddEnvironmentVariables("AHKFLOW_");

builder.Services.Configure<CliOptions>(builder.Configuration);

bool verbose = args.Any(a => a == "--verbose" || a == "-v");

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Is(verbose ? LogEventLevel.Information : LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .WriteTo.Console(
        standardErrorFromLevel: LogEventLevel.Verbose,
        outputTemplate: "{Message:lj}{NewLine}{Exception}")
    .CreateLogger();

builder.Services.AddSerilog();

builder.Services.AddSingleton<IAuthTokenProvider, NullAuthTokenProvider>();
builder.Services.AddTransient<BearerTokenHandler>();

CliOptions options = builder.Configuration.Get<CliOptions>() ?? new CliOptions();

builder.Services.AddHttpClient<IDownloadsApiClient>(client =>
    {
        if (!string.IsNullOrWhiteSpace(options.ApiBaseUrl))
            client.BaseAddress = new Uri(options.ApiBaseUrl);
    })
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

builder.Services.AddHttpClient<IProfilesApiClient>(client =>
    {
        if (!string.IsNullOrWhiteSpace(options.ApiBaseUrl))
            client.BaseAddress = new Uri(options.ApiBaseUrl);
    })
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

using IHost host = builder.Build();

RootCommand root = RootCli.Build(host.Services);
return await root.Parse(args).InvokeAsync();
```

Note: `AddHttpClient<TInterface>(...)` without a concrete type is unusual but legal — the concrete `DownloadsApiClient`/`ProfilesApiClient` registrations are added in Phase 3 by replacing this with `AddHttpClient<TInterface, TImpl>(...)`. For Phase 1, no impl is registered, so `IDownloadsApiClient`/`IProfilesApiClient` are not resolvable yet — fine because no command uses them in Phase 1.

Actually, simpler for Phase 1: don't register the typed clients yet. Replace the two `AddHttpClient<...>(...)` blocks with a comment until Phase 3. Use this instead:

```csharp
// HttpClient registrations for IDownloadsApiClient and IProfilesApiClient land in backlog 028.
```

Use the comment-out version. The two `AddHttpClient<...>` blocks above stay in this plan as the **target** shape so Phase 3 knows the structure.

- [ ] **Step 3: Run the help command**

Run: `dotnet run --project src/Tools/AHKFlowApp.CLI -- --help`
Expected: prints help text starting with `Description:` and `ahkflow — AHKFlowApp CLI`, exits 0. No subcommands listed yet.

- [ ] **Step 4: Run with no args**

Run: `dotnet run --project src/Tools/AHKFlowApp.CLI`
Expected: System.CommandLine prints required-command usage info or help; exits non-zero (acceptable — this is the "no command provided" path).

- [ ] **Step 5: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(017): wire host, DI, Serilog (stderr), and root command"
```

---

### Task 6: BearerTokenHandler unit test

**Files:**
- Create: `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj`
- Create: `tests/AHKFlowApp.CLI.Tests/Services/BearerTokenHandlerTests.cs`
- Modify: `AHKFlowApp.slnx`

- [ ] **Step 1: Create `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="NSubstitute" />
    <PackageReference Include="coverlet.collector">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\Tools\AHKFlowApp.CLI\AHKFlowApp.CLI.csproj" />
  </ItemGroup>

</Project>
```

- [ ] **Step 2: Add the test project to `AHKFlowApp.slnx`**

Inside the existing `<Folder Name="/tests/">` block, add:

```xml
    <Project Path="tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj" />
```

- [ ] **Step 3: Create the failing test `tests/AHKFlowApp.CLI.Tests/Services/BearerTokenHandlerTests.cs`**

```csharp
using System.Net;
using System.Net.Http.Headers;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class BearerTokenHandlerTests
{
    [Fact]
    public async Task SendAsync_AttachesBearerToken()
    {
        IAuthTokenProvider tokenProvider = Substitute.For<IAuthTokenProvider>();
        tokenProvider.GetTokenAsync(Arg.Any<CancellationToken>()).Returns("test-token-123");

        HttpRequestMessage capturedRequest = null!;
        var inner = new CapturingHandler(req => capturedRequest = req);

        var handler = new BearerTokenHandler(tokenProvider) { InnerHandler = inner };
        var client = new HttpClient(handler);

        await client.GetAsync("https://example.test/foo");

        capturedRequest.Headers.Authorization.Should().NotBeNull();
        capturedRequest.Headers.Authorization!.Scheme.Should().Be("Bearer");
        capturedRequest.Headers.Authorization.Parameter.Should().Be("test-token-123");
    }

    private sealed class CapturingHandler(Action<HttpRequestMessage> capture) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct)
        {
            capture(request);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
        }
    }
}
```

- [ ] **Step 4: Run the test**

Run: `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release`
Expected: test passes (the implementation already exists from Task 3).

- [ ] **Step 5: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests AHKFlowApp.slnx
git commit -m "test(017): cover BearerTokenHandler header attachment"
```

---

### Task 7: CI smoke step + remove from out-of-scope

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.claude/CLAUDE.md`

- [ ] **Step 1: Add CLI smoke step to `.github/workflows/ci.yml`**

Insert this step **after** the existing `- run: dotnet build --configuration Release --no-restore` line (around line 27) and **before** the `- name: Test with coverage` step:

```yaml
      - name: CLI --help smoke test
        run: dotnet run --project src/Tools/AHKFlowApp.CLI --no-build --configuration Release -- --help
```

- [ ] **Step 2: Update `.claude/CLAUDE.md` Out of Scope section**

Find the block that begins with `## Out of Scope` and remove the line:

```
- CLI application (`src/Tools/AHKFlowApp.CLI`) — planned, directory not yet created
```

Leave the other entries untouched.

- [ ] **Step 3: Run dotnet format**

Run: `dotnet format`
Expected: completes; may make whitespace changes — review the diff and amend if needed.

- [ ] **Step 4: Run the full test suite**

Run: `dotnet build --configuration Release && dotnet test --configuration Release --no-build`
Expected: all tests pass (existing + new BearerTokenHandlerTests).

- [ ] **Step 5: Run `dotnet format --verify-no-changes`**

Run: `dotnet format --verify-no-changes`
Expected: exits 0 (CI runs this same check).

- [ ] **Step 6: Mark backlog 017 complete**

Edit `.claude/backlog/017-scaffold-cli-project.md`:
- Change every `- [ ]` to `- [x]` in the Acceptance criteria block.
- Add a `**Completed:** 2026-MM-DD (PR #NNN)` line right after the last AC, where the date is today's date and the PR number is filled in once the PR is created (leave as `(PR #TBD)` and update post-merge).

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/ci.yml .claude/CLAUDE.md .claude/backlog/017-scaffold-cli-project.md
git commit -m "ci(017): add ahkflow --help smoke; close backlog 017"
```

---

### Task 8: Open PR #1

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/017-cli-foundation
```

- [ ] **Step 2: Create the PR with `gh`**

```bash
gh pr create --title "feat(017): scaffold AHKFlowApp.CLI" --body "$(cat <<'EOF'
## Summary
- Scaffolds `src/Tools/AHKFlowApp.CLI` console project (target binary `ahkflow`).
- Wires Microsoft.Extensions.Hosting + System.CommandLine + Serilog (stderr by default).
- Adds `IAuthTokenProvider` stub (`NullAuthTokenProvider`), `BearerTokenHandler`, and API client interfaces.
- Adds `tests/AHKFlowApp.CLI.Tests` with handler unit test.
- Adds CI smoke step `ahkflow --help`.

## Test plan
- [ ] CI green
- [ ] `dotnet run --project src/Tools/AHKFlowApp.CLI -- --help` prints root help text locally
- [ ] `dotnet test tests/AHKFlowApp.CLI.Tests` passes locally

Spec: `docs/superpowers/specs/2026-05-08-cli-foundation-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: After merge, update backlog 017 PR number**

Once PR #1 is merged, edit `.claude/backlog/017-scaffold-cli-project.md` to replace `(PR #TBD)` with the real PR number, push as a small follow-up commit on `main` only if not yet on main (otherwise include in the next phase's branch).

---

# Phase 2 — Backlog 029: CLI authentication (PR #2)

**Branch:** Start fresh from updated `main` after PR #1 merges.

```bash
git checkout main
git pull
git checkout -b feature/029-cli-authentication
```

### Task 9: Add MSAL packages

**Files:**
- Modify: `Directory.Packages.props`
- Modify: `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`

- [ ] **Step 1: Add MSAL packages**

```bash
dotnet add src/Tools/AHKFlowApp.CLI package Microsoft.Identity.Client
dotnet add src/Tools/AHKFlowApp.CLI package Microsoft.Identity.Client.Extensions.Msal
```

- [ ] **Step 2: Verify CPM**

Confirm `Directory.Packages.props` got both `<PackageVersion ... />` lines and `AHKFlowApp.CLI.csproj` got unversioned `<PackageReference ... />` lines. Strip any `Version="..."` that landed in the csproj.

- [ ] **Step 3: Build**

Run: `dotnet build --configuration Release`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add Directory.Packages.props src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj
git commit -m "chore(029): add MSAL.NET packages"
```

---

### Task 10: MsalCacheConfig and MsalDeviceCodeTokenProvider

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Auth/MsalCacheConfig.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/MsalDeviceCodeTokenProvider.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`

- [ ] **Step 1: Create `Auth/MsalCacheConfig.cs`**

```csharp
using Microsoft.Identity.Client.Extensions.Msal;

namespace AHKFlowApp.CLI.Auth;

public static class MsalCacheConfig
{
    public const string CacheFileName = "msal-cache.bin3";

    public static StorageCreationProperties Build(string clientId)
    {
        string cacheDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AHKFlowApp");

        Directory.CreateDirectory(cacheDir);

        return new StorageCreationPropertiesBuilder(CacheFileName, cacheDir)
            .WithLinuxKeyring(
                schemaName: "com.segocom.ahkflowapp.tokencache",
                collection: MsalCacheHelper.LinuxKeyRingDefaultCollection,
                label: "AHKFlowApp MSAL token cache",
                attr1: new KeyValuePair<string, string>("Version", "1"),
                attr2: new KeyValuePair<string, string>("ProductGroup", "AHKFlowApp"))
            .WithMacKeyChain(
                serviceName: "ahkflowapp-msal-cache",
                accountName: "ahkflowapp")
            .Build();
    }
}
```

The Linux keyring/macOS keychain options are required by `Microsoft.Identity.Client.Extensions.Msal` even on Windows-primary deployments — they're no-ops on Windows where DPAPI is used.

- [ ] **Step 2: Create `Services/MsalDeviceCodeTokenProvider.cs`**

```csharp
using AHKFlowApp.CLI.Auth;
using AHKFlowApp.CLI.Exceptions;
using Microsoft.Extensions.Options;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Extensions.Msal;

namespace AHKFlowApp.CLI.Services;

public sealed class MsalDeviceCodeTokenProvider : IAuthTokenProvider
{
    private readonly IPublicClientApplication _pca;
    private readonly string[] _scopes;
    private readonly Lazy<Task<MsalCacheHelper>> _cacheHelper;

    public MsalDeviceCodeTokenProvider(IOptions<CliOptions> options)
    {
        CliOptions o = options.Value;
        if (string.IsNullOrWhiteSpace(o.ClientId)) throw new InvalidOperationException("ClientId not configured.");
        if (string.IsNullOrWhiteSpace(o.TenantId)) throw new InvalidOperationException("TenantId not configured.");

        _pca = PublicClientApplicationBuilder.Create(o.ClientId)
            .WithAuthority($"https://login.microsoftonline.com/{o.TenantId}")
            .WithRedirectUri("http://localhost")
            .Build();

        _scopes = [$"api://{o.ClientId}/access_as_user"];

        _cacheHelper = new Lazy<Task<MsalCacheHelper>>(async () =>
        {
            MsalCacheHelper helper = await MsalCacheHelper.CreateAsync(MsalCacheConfig.Build(o.ClientId));
            helper.RegisterCache(_pca.UserTokenCache);
            return helper;
        });
    }

    public async Task<string> GetTokenAsync(CancellationToken ct)
    {
        await _cacheHelper.Value;

        IAccount? account = (await _pca.GetAccountsAsync()).FirstOrDefault();
        if (account is null)
            throw new NotAuthenticatedException("Not signed in. Run 'ahkflow login' first.");

        try
        {
            AuthenticationResult result = await _pca.AcquireTokenSilent(_scopes, account).ExecuteAsync(ct);
            return result.AccessToken;
        }
        catch (MsalUiRequiredException)
        {
            throw new NotAuthenticatedException("Sign-in expired. Run 'ahkflow login' to refresh.");
        }
    }

    public async Task<LoginResult> LoginAsync(CancellationToken ct)
    {
        await _cacheHelper.Value;

        IAccount? account = (await _pca.GetAccountsAsync()).FirstOrDefault();
        if (account is not null)
        {
            try
            {
                AuthenticationResult silent = await _pca.AcquireTokenSilent(_scopes, account).ExecuteAsync(ct);
                return new LoginResult(silent.Account.Username, WasAlreadySignedIn: true);
            }
            catch (MsalUiRequiredException)
            {
                // Cached account exists but tokens expired — fall through to interactive login.
            }
        }

        AuthenticationResult result = await _pca.AcquireTokenWithDeviceCode(_scopes, callback =>
        {
            Console.Error.WriteLine(callback.Message);
            return Task.CompletedTask;
        }).ExecuteAsync(ct);

        return new LoginResult(result.Account.Username, WasAlreadySignedIn: false);
    }

    public async Task LogoutAsync(CancellationToken ct)
    {
        await _cacheHelper.Value;

        foreach (IAccount account in await _pca.GetAccountsAsync())
            await _pca.RemoveAsync(account);

        try
        {
            string cacheDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AHKFlowApp");
            string cacheFile = Path.Combine(cacheDir, MsalCacheConfig.CacheFileName);
            if (File.Exists(cacheFile))
                File.Delete(cacheFile);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort — accounts removed via PCA is enough.
        }
    }
}
```

- [ ] **Step 3: Replace the stub registration in `Program.cs`**

Find the line:

```csharp
builder.Services.AddSingleton<IAuthTokenProvider, NullAuthTokenProvider>();
```

Replace with:

```csharp
builder.Services.AddSingleton<IAuthTokenProvider, MsalDeviceCodeTokenProvider>();
```

- [ ] **Step 4: Build**

Run: `dotnet build --configuration Release`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(029): MsalDeviceCodeTokenProvider with persisted cache"
```

---

### Task 11: LoginCommand

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/LoginCommand.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`

- [ ] **Step 1: Create `Commands/LoginCommand.cs`**

```csharp
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands;

public static class LoginCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("login", "Sign in via device-code flow.");

        cmd.SetAction(async (parseResult, ct) =>
        {
            IAuthTokenProvider provider = services.GetRequiredService<IAuthTokenProvider>();
            try
            {
                LoginResult result = await provider.LoginAsync(ct);
                string verb = result.WasAlreadySignedIn ? "Already signed in" : "Signed in";
                Console.Out.WriteLine($"{verb} as {result.Username}");
                return 0;
            }
            catch (NotAuthenticatedException ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 3;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Login failed: {ex.Message}");
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 2: Wire in `RootCli.cs`**

Modify `Commands/RootCli.cs` — uncomment / add the LoginCommand line:

```csharp
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands;

public static class RootCli
{
    public static RootCommand Build(IServiceProvider services)
    {
        RootCommand root = new("ahkflow — AHKFlowApp CLI");
        root.Subcommands.Add(LoginCommand.Build(services));
        return root;
    }
}
```

- [ ] **Step 3: Verify help shows the subcommand**

Run: `dotnet run --project src/Tools/AHKFlowApp.CLI -- --help`
Expected: output includes a `Commands:` section listing `login`.

- [ ] **Step 4: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(029): add ahkflow login command"
```

---

### Task 12: LogoutCommand

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/LogoutCommand.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`

- [ ] **Step 1: Create `Commands/LogoutCommand.cs`**

```csharp
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands;

public static class LogoutCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("logout", "Clear cached credentials.");

        cmd.SetAction(async (parseResult, ct) =>
        {
            IAuthTokenProvider provider = services.GetRequiredService<IAuthTokenProvider>();
            try
            {
                await provider.LogoutAsync(ct);
                Console.Out.WriteLine("Signed out");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Logout failed: {ex.Message}");
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 2: Wire in `RootCli.cs`**

```csharp
root.Subcommands.Add(LogoutCommand.Build(services));
```

Place this line right after the `LoginCommand` line.

- [ ] **Step 3: Build and verify**

Run: `dotnet build --configuration Release && dotnet run --project src/Tools/AHKFlowApp.CLI -- --help`
Expected: help lists `login` and `logout`.

- [ ] **Step 4: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(029): add ahkflow logout command"
```

---

### Task 13: Update `setup-entra-app.ps1`

**Files:**
- Modify: `scripts/setup-entra-app.ps1`

- [ ] **Step 1: Add `publicClient.redirectUris` PATCH**

Locate the section that PATCHes `spa.redirectUris` (search for `$spaJson = @{`). Immediately after the `Write-Host "Redirect URIs set: ..."` line that follows that block, append:

```powershell

# ---------------------------------------------------------------------------
# Add public-client redirect URI for the CLI's MSAL device-code flow
# (separate collection from spa.redirectUris)
# ---------------------------------------------------------------------------
$publicClientUri = 'http://localhost'

$currentPublicClient = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'publicClient.redirectUris' -o json 2>$null)
if (-not $currentPublicClient) { $currentPublicClient = @() }

if ($publicClientUri -notin $currentPublicClient) {
    $merged = @($currentPublicClient + $publicClientUri | Select-Object -Unique)
    $publicClientJson = @{ publicClient = @{ redirectUris = $merged } } | ConvertTo-Json -Depth 5 -Compress
    Invoke-GraphPatch -ObjectId $objectId -JsonBody $publicClientJson
    Wait-ForCondition -Description "publicClient redirect URI" -Condition {
        $configured = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'publicClient.redirectUris' -o json 2>$null)
        return $publicClientUri -in $configured
    }
    Write-Host "Added publicClient redirect URI: $publicClientUri"
} else {
    Write-Host "publicClient redirect URI already present: $publicClientUri"
}
```

- [ ] **Step 2: Add `isFallbackPublicClient` PATCH**

Right after the public-client redirect block, append:

```powershell

# ---------------------------------------------------------------------------
# Enable public-client flows so MSAL device-code flow does not need a secret
# ---------------------------------------------------------------------------
$currentFallback = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'isFallbackPublicClient' -o json 2>$null)
if ($currentFallback -ne $true) {
    $fallbackJson = @{ isFallbackPublicClient = $true } | ConvertTo-Json -Compress
    Invoke-GraphPatch -ObjectId $objectId -JsonBody $fallbackJson
    Wait-ForCondition -Description "isFallbackPublicClient = true" -Condition {
        $val = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'isFallbackPublicClient' -o json 2>$null)
        return $val -eq $true
    }
    Write-Host "Enabled public-client flows (isFallbackPublicClient=true)"
} else {
    Write-Host "Public-client flows already enabled"
}
```

- [ ] **Step 3: Manual smoke test on a dev app registration**

If the user has an Entra dev tenant available, run the script against it and verify with:
```bash
az ad app show --id <appId> --query 'publicClient.redirectUris'
az ad app show --id <appId> --query 'isFallbackPublicClient'
```
Expected: `["http://localhost"]` and `true` respectively. If no dev tenant available, document this manual step in the PR description and skip live verification.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-entra-app.ps1
git commit -m "feat(029): setup-entra-app supports CLI public-client flows"
```

---

### Task 14: Update auth doc and close backlog 029

**Files:**
- Modify: `docs/architecture/authentication.md`
- Modify: `.claude/backlog/029-cli-authentication.md`

- [ ] **Step 1: Replace the "CLI authentication" section in `docs/architecture/authentication.md`**

Find the trailing section:

```markdown
## CLI authentication

Deferred to backlog item 029. Will use MSAL.NET device-code flow as a public-client registration on the same Entra app.
```

Replace with:

```markdown
## CLI authentication

The `ahkflow` CLI uses MSAL.NET device-code flow against the same Entra app registration as the SPA. The app registration carries both the SPA redirect URIs and a public-client redirect URI (`http://localhost`); `isFallbackPublicClient` is set to `true` so the CLI can acquire tokens without a client secret.

| Component | Location | Purpose |
|---|---|---|
| `IAuthTokenProvider` | `src/Tools/AHKFlowApp.CLI/Services/` | Abstraction over token acquisition (silent / device-code / logout) |
| `MsalDeviceCodeTokenProvider` | `src/Tools/AHKFlowApp.CLI/Services/` | MSAL.NET implementation; single-account model |
| `MsalCacheConfig` | `src/Tools/AHKFlowApp.CLI/Auth/` | Token cache file (`%LOCALAPPDATA%/AHKFlowApp/msal-cache.bin3`) with platform-native encryption (DPAPI on Windows, Keychain on macOS, libsecret on Linux) |
| `BearerTokenHandler` | `src/Tools/AHKFlowApp.CLI/Services/` | DelegatingHandler — attaches `Authorization: Bearer <token>` to every API request |

Scope: `api://{ClientId}/access_as_user` (same as the UI). Configuration values come from the CLI's `appsettings.json` and `AHKFLOW_*` environment variables.

`ahkflow login` triggers device-code flow; `ahkflow logout` removes all cached accounts. To switch identity, run `logout` then `login`.
```

- [ ] **Step 2: Mark backlog 029 complete**

Edit `.claude/backlog/029-cli-authentication.md`:
- Change every `- [ ]` to `- [x]` in the Acceptance criteria block.
- Add a `**Completed:** 2026-MM-DD (PR #TBD)` line right after the last AC.

- [ ] **Step 3: Format check**

Run: `dotnet format --verify-no-changes`
Expected: exits 0.

- [ ] **Step 4: Run all tests**

Run: `dotnet test --configuration Release`
Expected: all tests pass.

- [ ] **Step 5: Commit and open PR**

```bash
git add docs/architecture/authentication.md .claude/backlog/029-cli-authentication.md
git commit -m "docs(029): document CLI auth and close backlog 029"
git push -u origin feature/029-cli-authentication
gh pr create --title "feat(029): CLI authentication via MSAL device-code" --body "$(cat <<'EOF'
## Summary
- Replaces `NullAuthTokenProvider` with `MsalDeviceCodeTokenProvider`.
- Adds `ahkflow login` and `ahkflow logout` commands.
- Updates `scripts/setup-entra-app.ps1` to add public-client redirect URI and `isFallbackPublicClient: true`.
- Updates `docs/architecture/authentication.md`.

## Test plan
- [ ] CI green
- [ ] Run `setup-entra-app.ps1` against dev tenant, verify Graph manifest changes
- [ ] Manual: `dotnet run --project src/Tools/AHKFlowApp.CLI -- login` against dev API; verify device code printed and token cached
- [ ] Manual: `ahkflow login` again — confirm "Already signed in as ..." message
- [ ] Manual: `ahkflow logout` — confirm cache cleared

Spec: `docs/superpowers/specs/2026-05-08-cli-foundation-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

# Phase 3 — Backlog 028: Download command (PR #3)

**Branch:** Start fresh from updated `main` after PR #2 merges.

```bash
git checkout main
git pull
git checkout -b feature/028-cli-download
```

### Task 15: ProfilesApiClient implementation

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/ProfilesApiClient.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`

- [ ] **Step 1: Create `Services/ProfilesApiClient.cs`**

```csharp
using System.Net.Http.Json;

namespace AHKFlowApp.CLI.Services;

public sealed class ProfilesApiClient(HttpClient httpClient) : IProfilesApiClient
{
    public async Task<IReadOnlyList<ProfileSummary>> ListAsync(CancellationToken ct)
    {
        ProfileSummary[]? result = await httpClient.GetFromJsonAsync<ProfileSummary[]>(
            "api/v1/profiles", ct);
        return result ?? [];
    }
}
```

The `ProfileSummary(Guid Id, string Name)` record matches the API's `ProfileDto` fields by name (System.Text.Json deserializes case-insensitively by default).

- [ ] **Step 2: Update Program.cs HttpClient registration**

Find the comment line `// HttpClient registrations for IDownloadsApiClient and IProfilesApiClient land in backlog 028.` (added in Task 5 Step 2 if Phase 1 used the comment-out version). Replace it with:

```csharp
CliOptions options = builder.Configuration.Get<CliOptions>() ?? new CliOptions();

builder.Services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(client =>
    {
        if (!string.IsNullOrWhiteSpace(options.ApiBaseUrl))
            client.BaseAddress = new Uri(options.ApiBaseUrl);
    })
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();
```

If Phase 1 instead used the `AddHttpClient<IDownloadsApiClient>(...)` shape from Task 5, change the type parameter to `<IProfilesApiClient, ProfilesApiClient>` (full two-parameter form).

- [ ] **Step 3: Build**

Run: `dotnet build --configuration Release`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(028): add ProfilesApiClient (List)"
```

---

### Task 16: DownloadsApiClient implementation

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/DownloadsApiClient.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`

- [ ] **Step 1: Create `Services/DownloadsApiClient.cs`**

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.CLI.Exceptions;

namespace AHKFlowApp.CLI.Services;

public sealed class DownloadsApiClient(HttpClient httpClient) : IDownloadsApiClient
{
    public Task<DownloadResult> GetProfileScriptAsync(Guid profileId, CancellationToken ct) =>
        GetAsync($"api/v1/downloads/{profileId}", "ahkflow_profile.ahk", ct);

    public Task<DownloadResult> GetAllProfileScriptsZipAsync(CancellationToken ct) =>
        GetAsync("api/v1/downloads/zip", "ahkflow_scripts.zip", ct);

    private async Task<DownloadResult> GetAsync(string path, string fallbackFileName, CancellationToken ct)
    {
        using HttpResponseMessage resp = await httpClient.GetAsync(path, ct);

        if (resp.StatusCode == HttpStatusCode.Unauthorized)
            throw new NotAuthenticatedException("Authentication failed. Run 'ahkflow login'.");

        if (!resp.IsSuccessStatusCode)
        {
            string? detail = await TryReadProblemDetailAsync(resp, ct);
            throw new HttpRequestException(
                detail ?? resp.ReasonPhrase ?? $"HTTP {(int)resp.StatusCode}",
                inner: null,
                statusCode: resp.StatusCode);
        }

        byte[] bytes = await resp.Content.ReadAsByteArrayAsync(ct);
        string fileName = resp.Content.Headers.ContentDisposition?.FileName?.Trim('"') ?? fallbackFileName;
        string contentType = resp.Content.Headers.ContentType?.ToString() ?? "application/octet-stream";
        return new DownloadResult(bytes, fileName, contentType);
    }

    private static async Task<string?> TryReadProblemDetailAsync(HttpResponseMessage resp, CancellationToken ct)
    {
        string? mediaType = resp.Content.Headers.ContentType?.MediaType;
        if (mediaType is not "application/problem+json" and not "application/json")
            return null;
        try
        {
            ProblemDetailDto? pd = await resp.Content.ReadFromJsonAsync<ProblemDetailDto>(ct);
            return pd?.Detail;
        }
        catch
        {
            return null;
        }
    }

    private sealed record ProblemDetailDto(string? Detail);
}
```

For non-2xx (and non-401) responses the client reads the `detail` field from the RFC 9457 body when available and wraps it in `HttpRequestException(message, null, statusCode)` so `DownloadCommand` can both branch on `StatusCode` and surface the server's detail via `ex.Message`. The local `ProblemDetailDto` avoids dragging `Microsoft.AspNetCore.Mvc.Core` into the CLI just for one type; `ReadFromJsonAsync` uses web defaults (case-insensitive), so the lowercase `detail` JSON field binds correctly.

- [ ] **Step 2: Add registration to Program.cs**

Right after the `AddHttpClient<IProfilesApiClient, ProfilesApiClient>(...)` block from Task 15, add:

```csharp
builder.Services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(client =>
    {
        if (!string.IsNullOrWhiteSpace(options.ApiBaseUrl))
            client.BaseAddress = new Uri(options.ApiBaseUrl);
    })
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();
```

- [ ] **Step 3: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(028): add DownloadsApiClient"
```

---

### Task 17: DownloadCommand — args, profile resolution, output

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/CliFile.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Commands/DownloadCommand.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`

- [ ] **Step 1: Create `Services/CliFile.cs`**

```csharp
namespace AHKFlowApp.CLI.Services;

public static class CliFile
{
    public const string StdoutSentinel = "-";

    public static string ResolveOutputPath(string? userOutput, string defaultFileName) =>
        string.IsNullOrEmpty(userOutput) ? Path.Combine(Environment.CurrentDirectory, defaultFileName) : userOutput;

    public static async Task WriteAsync(string outputPath, byte[] bytes, bool force, CancellationToken ct)
    {
        if (outputPath == StdoutSentinel)
        {
            using Stream stdout = Console.OpenStandardOutput();
            await stdout.WriteAsync(bytes, ct);
            return;
        }

        if (File.Exists(outputPath) && !force)
            throw new IOException($"File '{outputPath}' exists. Use --force to overwrite.");

        await File.WriteAllBytesAsync(outputPath, bytes, ct);
    }
}
```

- [ ] **Step 2: Create `Commands/DownloadCommand.cs`**

```csharp
using System.Net;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands;

public static class DownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string?> profile = new("--profile") { Description = "Profile name to download." };
        Option<bool> all = new("--all") { Description = "Download all profiles as a zip." };
        Option<string?> output = new("--output", "-o") { Description = "Output path, or '-' for stdout." };
        Option<bool> force = new("--force") { Description = "Overwrite an existing output file." };

        Command cmd = new("download", "Download generated AHK scripts.")
        {
            profile, all, output, force
        };

        cmd.SetAction(async (parseResult, ct) =>
        {
            string? profileName = parseResult.GetValue(profile);
            bool isAll = parseResult.GetValue(all);
            string? outputPath = parseResult.GetValue(output);
            bool isForce = parseResult.GetValue(force);

            if ((profileName is null) == (!isAll))
            {
                Console.Error.WriteLine("Specify exactly one of --profile <name> or --all.");
                return 2;
            }

            try
            {
                IDownloadsApiClient downloads = services.GetRequiredService<IDownloadsApiClient>();

                DownloadResult result;
                string defaultFileName;

                if (isAll)
                {
                    result = await downloads.GetAllProfileScriptsZipAsync(ct);
                    defaultFileName = "ahkflow_scripts.zip";
                }
                else
                {
                    IProfilesApiClient profiles = services.GetRequiredService<IProfilesApiClient>();
                    IReadOnlyList<ProfileSummary> all_ = await profiles.ListAsync(ct);
                    ProfileSummary? match = all_.FirstOrDefault(p =>
                        string.Equals(p.Name, profileName, StringComparison.OrdinalIgnoreCase));
                    if (match is null)
                    {
                        string available = all_.Count == 0 ? "(none)" : string.Join(", ", all_.Select(p => p.Name));
                        Console.Error.WriteLine($"Profile '{profileName}' not found. Available: {available}");
                        return 2;
                    }
                    result = await downloads.GetProfileScriptAsync(match.Id, ct);
                    defaultFileName = result.FileName;
                }

                string resolved = CliFile.ResolveOutputPath(outputPath, defaultFileName);
                await CliFile.WriteAsync(resolved, result.Bytes, isForce, ct);

                if (resolved != CliFile.StdoutSentinel)
                    Console.Out.WriteLine($"Wrote {result.Bytes.Length} bytes to {resolved}");
                return 0;
            }
            catch (NotAuthenticatedException ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 3;
            }
            catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
            {
                Console.Error.WriteLine($"Profile '{profileName}' not found on the server.");
                return 2;
            }
            catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Forbidden)
            {
                Console.Error.WriteLine($"Forbidden: {ex.Message}");
                return 1;
            }
            catch (IOException ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 2;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Download failed: {ex.Message}");
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 3: Wire in `RootCli.cs`**

Add after the `LogoutCommand` line:

```csharp
root.Subcommands.Add(DownloadCommand.Build(services));
```

- [ ] **Step 4: Build and check help output**

Run: `dotnet build --configuration Release && dotnet run --project src/Tools/AHKFlowApp.CLI -- download --help`
Expected: shows `--profile`, `--all`, `--output|-o`, `--force` options.

- [ ] **Step 5: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(028): add ahkflow download command"
```

---

### Task 18: CliRunner test helper

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj`
- Create: `tests/AHKFlowApp.CLI.Tests/CliRunner.cs`

- [ ] **Step 1: Add references to TestUtilities and the API project**

Modify `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj`. Inside the `<ItemGroup>` containing `<ProjectReference>`, add:

```xml
    <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.API\AHKFlowApp.API.csproj" />
```

Also add `Microsoft.AspNetCore.Mvc.Testing` package reference (CPM-managed) to the same file:

```xml
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
```

- [ ] **Step 2: Create `CliRunner.cs`**

```csharp
using AHKFlowApp.CLI.Commands;
using AHKFlowApp.CLI.Services;
using AHKFlowApp.TestUtilities.Auth;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using System.CommandLine;
using System.Text;

namespace AHKFlowApp.CLI.Tests;

public sealed record CliRunResult(int ExitCode, string Stdout, byte[] StdoutBytes, string Stderr);

public static class CliRunner
{
    public static async Task<CliRunResult> RunAsync(
        WebApplicationFactory<Program> apiFactory,
        IAuthTokenProvider? authOverride,
        params string[] args)
    {
        ServiceCollection sc = new();

        IAuthTokenProvider authProvider = authOverride ?? StubProvider("test-token");
        sc.AddSingleton(authProvider);
        sc.AddTransient<BearerTokenHandler>();

        sc.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(client =>
            client.BaseAddress = apiFactory.Server.BaseAddress)
          .AddHttpMessageHandler<BearerTokenHandler>()
          .ConfigurePrimaryHttpMessageHandler(() => apiFactory.Server.CreateHandler());

        sc.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(client =>
            client.BaseAddress = apiFactory.Server.BaseAddress)
          .AddHttpMessageHandler<BearerTokenHandler>()
          .ConfigurePrimaryHttpMessageHandler(() => apiFactory.Server.CreateHandler());

        using ServiceProvider services = sc.BuildServiceProvider();

        // Capture stdout as bytes (download -o - writes raw bytes) AND as text.
        using MemoryStream stdoutStream = new();
        using StreamWriter stdoutWriter = new(stdoutStream, new UTF8Encoding(false)) { AutoFlush = true };
        TextWriter origOut = Console.Out;
        Stream origOutStream = Console.OpenStandardOutput();

        StringBuilder stderrSb = new();
        TextWriter origErr = Console.Error;

        try
        {
            Console.SetOut(stdoutWriter);
            Console.SetError(new StringWriter(stderrSb));
            Console.SetIn(TextReader.Null);

            // Replace the OpenStandardOutput stream — DownloadCommand uses it for `-o -`.
            // The default Console.OpenStandardOutput() can't be redirected via SetOut alone
            // because it returns a new stream each call. We provide a thin shim by
            // temporarily redirecting the underlying file descriptor on Windows is
            // intrusive; instead, the test for `-o -` runs against the file output path
            // and a separate test asserts the stdout sentinel is interpreted correctly.

            RootCommand root = RootCli.Build(services);
            int exit = await root.Parse(args).InvokeAsync();

            stdoutWriter.Flush();
            byte[] stdoutBytes = stdoutStream.ToArray();
            string stdout = Encoding.UTF8.GetString(stdoutBytes);
            return new CliRunResult(exit, stdout, stdoutBytes, stderrSb.ToString());
        }
        finally
        {
            Console.SetOut(origOut);
            Console.SetError(origErr);
        }
    }

    public static IAuthTokenProvider StubProvider(string token)
    {
        IAuthTokenProvider p = Substitute.For<IAuthTokenProvider>();
        p.GetTokenAsync(Arg.Any<CancellationToken>()).Returns(token);
        return p;
    }

    public static WebApplicationFactory<Program> AuthAs(
        CustomWebApplicationFactory factory, Guid oid) =>
        factory.WithTestAuth(b => b.WithOid(oid));
}
```

The shim limitation noted in the comment is resolved in Task 21 (stdout-bytes test) by using a separate runner that overrides the OpenStandardOutput stream. For now this CliRunner is sufficient for the file-output tests in Tasks 19-20.

- [ ] **Step 3: Create `tests/AHKFlowApp.CLI.Tests/Collections.cs`**

xUnit collection definitions are scoped per assembly, so the new test project needs its own `[CollectionDefinition("WebApi")]` paired with `SqlContainerFixture` (the one in `tests/AHKFlowApp.API.Tests/Collections.cs` is not visible here). Without this file, the `[Collection("WebApi")]` classes added in Tasks 19-22 will run but xUnit will not construct the fixture, so `SqlContainerFixture` constructor injection fails.

```csharp
using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.CLI.Tests;

[CollectionDefinition("WebApi")]
public sealed class WebApiCollection : ICollectionFixture<SqlContainerFixture>;
```

- [ ] **Step 4: Build**

Run: `dotnet build tests/AHKFlowApp.CLI.Tests --configuration Release`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests
git commit -m "test(028): add CliRunner harness"
```

---

### Task 19: Integration test — happy path per-profile download

**Files:**
- Create: `tests/AHKFlowApp.CLI.Tests/Commands/DownloadCommandTests.cs`

- [ ] **Step 1: Write the test (failing first run will validate the harness end-to-end)**

```csharp
using AHKFlowApp.CLI.Tests;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Commands;

[Collection("WebApi")]
public sealed class DownloadCommandTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task Download_ByProfileName_WritesFileWithServerFileName()
    {
        Guid oid = Guid.NewGuid();
        Guid profileId = await SeedDefaultProfile(oid, name: "Work");

        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);
        string tempDir = NewTempDir();
        string outputPath = Path.Combine(tempDir, "out.ahk");

        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth,
                authOverride: null,
                "download", "--profile", "Work", "-o", outputPath);

            run.ExitCode.Should().Be(0);
            File.Exists(outputPath).Should().BeTrue();
            byte[] written = await File.ReadAllBytesAsync(outputPath);
            written.Length.Should().BeGreaterThan(0);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    private async Task<Guid> SeedDefaultProfile(Guid ownerOid, string name)
    {
        // Seed a profile via the API so the test exercises the same code path
        // the CLI will hit. Uses the WithTestAuth client.
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, ownerOid);
        using HttpClient client = auth.CreateClient();

        // Trigger default-profile seeding by listing first.
        await client.GetAsync("/api/v1/profiles");

        // Read the seeded default profile, rename it to `name`.
        var list = await client.GetFromJsonAsync<ProfileListItem[]>("/api/v1/profiles");
        ProfileListItem first = list![0];

        // PUT to rename
        var update = new { Name = name, IsDefault = true, HeaderTemplate = first.HeaderTemplate, FooterTemplate = first.FooterTemplate };
        HttpResponseMessage resp = await client.PutAsJsonAsync($"/api/v1/profiles/{first.Id}", update);
        resp.EnsureSuccessStatusCode();

        return first.Id;
    }

    private sealed record ProfileListItem(Guid Id, string Name, bool IsDefault, string HeaderTemplate, string FooterTemplate);

    private static string NewTempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), "ahkflow-cli-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 2: Run the test**

Run: `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "Download_ByProfileName_WritesFileWithServerFileName"`
Expected: passes (Testcontainers spins up SQL Server; takes 30–60s on first run).

If it fails because the API's `update` PUT shape differs, inspect `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs` and adjust the `update` anonymous object to match `UpdateProfileDto` exactly.

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests
git commit -m "test(028): cover download by profile name"
```

---

### Task 20: Integration tests — error paths (not signed in, profile not found, file collision, --force)

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/DownloadCommandTests.cs`

- [ ] **Step 1: Add the test for "not signed in"**

Append inside the existing `DownloadCommandTests` class:

```csharp
    [Fact]
    public async Task Download_NotSignedIn_Exit3()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");

        // Don't apply WithTestAuth — but keep the fixture for DB seeding.
        // For the no-auth case we use a stub IAuthTokenProvider that throws.
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        var throwingProvider = NSubstitute.Substitute.For<AHKFlowApp.CLI.Services.IAuthTokenProvider>();
        throwingProvider.GetTokenAsync(NSubstitute.Arg.Any<CancellationToken>())
            .Returns<Task<string>>(_ => throw new AHKFlowApp.CLI.Exceptions.NotAuthenticatedException("Not signed in. Run 'ahkflow login' first."));

        string tempDir = NewTempDir();
        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth,
                authOverride: throwingProvider,
                "download", "--profile", "Work", "-o", Path.Combine(tempDir, "out.ahk"));

            run.ExitCode.Should().Be(3);
            run.Stderr.Should().Contain("Not signed in");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
```

- [ ] **Step 2: Add the "profile not found" test**

```csharp
    [Fact]
    public async Task Download_ProfileNotFound_Exit2_ListsAvailable()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        string tempDir = NewTempDir();
        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth, null,
                "download", "--profile", "Nonexistent", "-o", Path.Combine(tempDir, "out.ahk"));

            run.ExitCode.Should().Be(2);
            run.Stderr.Should().Contain("Profile 'Nonexistent' not found");
            run.Stderr.Should().Contain("Available: Work");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
```

- [ ] **Step 3: Add file-collision tests**

```csharp
    [Fact]
    public async Task Download_FileExists_NoForce_Exit2_FileUntouched()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        string tempDir = NewTempDir();
        string outputPath = Path.Combine(tempDir, "existing.ahk");
        await File.WriteAllTextAsync(outputPath, "DO NOT OVERWRITE");

        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth, null,
                "download", "--profile", "Work", "-o", outputPath);

            run.ExitCode.Should().Be(2);
            run.Stderr.Should().Contain("Use --force");
            (await File.ReadAllTextAsync(outputPath)).Should().Be("DO NOT OVERWRITE");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task Download_FileExists_WithForce_Overwrites()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        string tempDir = NewTempDir();
        string outputPath = Path.Combine(tempDir, "existing.ahk");
        await File.WriteAllTextAsync(outputPath, "OLD CONTENT");

        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth, null,
                "download", "--profile", "Work", "-o", outputPath, "--force");

            run.ExitCode.Should().Be(0);
            (await File.ReadAllTextAsync(outputPath)).Should().NotBe("OLD CONTENT");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
```

- [ ] **Step 4: Add mutually-exclusive args tests**

```csharp
    [Fact]
    public async Task Download_NeitherProfileNorAll_Exit2()
    {
        Guid oid = Guid.NewGuid();
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        CliRunResult run = await CliRunner.RunAsync(auth, null, "download");

        run.ExitCode.Should().Be(2);
        run.Stderr.Should().Contain("--profile");
        run.Stderr.Should().Contain("--all");
    }

    [Fact]
    public async Task Download_BothProfileAndAll_Exit2()
    {
        Guid oid = Guid.NewGuid();
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        CliRunResult run = await CliRunner.RunAsync(
            auth, null,
            "download", "--profile", "Work", "--all");

        run.ExitCode.Should().Be(2);
    }
```

- [ ] **Step 5: Run the new tests**

Run: `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release`
Expected: all five new tests pass alongside the existing happy-path test.

- [ ] **Step 6: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests
git commit -m "test(028): cover download error paths"
```

---

### Task 21: Integration tests — `--all` zip download (file output and stdout)

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/DownloadCommandTests.cs`

- [ ] **Step 1: Add the `--all` test that writes a zip file**

Append inside `DownloadCommandTests`:

```csharp
    [Fact]
    public async Task DownloadAll_ToFile_WritesZipWithEntries()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        string tempDir = NewTempDir();
        string outputPath = Path.Combine(tempDir, "scripts.zip");

        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth, null,
                "download", "--all", "-o", outputPath);

            run.ExitCode.Should().Be(0);
            File.Exists(outputPath).Should().BeTrue();

            using FileStream fs = File.OpenRead(outputPath);
            using System.IO.Compression.ZipArchive archive = new(fs, System.IO.Compression.ZipArchiveMode.Read);
            archive.Entries.Should().HaveCount(1);
            archive.Entries[0].Name.Should().Be("ahkflow_Work.ahk");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
```

- [ ] **Step 2: Add the `-o -` stdout test**

Note: capturing the raw bytes from `Console.OpenStandardOutput()` requires redirecting standard output at the OS level, not just `Console.SetOut`. The simplest reliable approach inside an in-process test is to launch the CLI as a subprocess. For this single test, do that:

```csharp
    [Fact]
    public async Task DownloadAll_ToStdout_PrintsZipBytes()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");

        // Determine the API base URL the subprocess should call.
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);
        // The in-process Kestrel-less factory can't be reached via HTTP from a child
        // process. Instead, launch the API as a real Kestrel server on a random port
        // and point the CLI at it via env vars.
        // For simplicity in the first pass, this test is marked Skip — covered by
        // Task 22 (stdout/stderr split test) which uses Console.SetOut.

        await Task.CompletedTask;
    }
```

Mark this test as `[Fact(Skip = "Subprocess + Kestrel required; covered conceptually by Task 22 stdout/stderr split test.")]` and document the limitation.

The plan accepts the gap: stdout-byte-level testing for `-o -` is out of scope for Phase 3 because in-process testing can't fully redirect the underlying stdout file descriptor. The Task 22 test below covers the **mixing concern** (logs vs script bytes on stdout) using `Console.SetOut`. End-to-end stdout-byte verification is a manual smoke step in the PR description.

- [ ] **Step 3: Run the new test**

Run: `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "DownloadAll"`
Expected: `DownloadAll_ToFile_WritesZipWithEntries` passes; `DownloadAll_ToStdout_PrintsZipBytes` is skipped.

- [ ] **Step 4: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests
git commit -m "test(028): cover --all zip download"
```

---

### Task 22: Stdout/stderr split test (Serilog stays off stdout)

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/DownloadCommandTests.cs`

- [ ] **Step 1: Add the test**

```csharp
    [Fact]
    public async Task Download_VerboseLogs_GoToStderr_NotStdout()
    {
        Guid oid = Guid.NewGuid();
        await SeedDefaultProfile(oid, "Work");
        WebApplicationFactory<Program> auth = CliRunner.AuthAs(_factory, oid);

        string tempDir = NewTempDir();
        string outputPath = Path.Combine(tempDir, "out.ahk");

        try
        {
            CliRunResult run = await CliRunner.RunAsync(
                auth, null,
                "--verbose", "download", "--profile", "Work", "-o", outputPath);

            run.ExitCode.Should().Be(0);

            // The "Wrote N bytes to ..." line is the only thing that should land on stdout.
            // Any Serilog event on stdout (e.g. default WriteTo.Console without
            // standardErrorFromLevel) would corrupt `download -o -` and is a regression.
            run.Stdout.Trim().Should().Be($"Wrote {new FileInfo(outputPath).Length} bytes to {outputPath}");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
```

`--verbose` is a recursive root option (see `RootCli.VerboseOption`), so it can appear before or after `download`. `Program.cs` pre-parses `args` for it and sets the Serilog minimum to `Information`, while `standardErrorFromLevel: LogEventLevel.Verbose` keeps every event off stdout. This test guards both: that `--verbose` is recognized (no parse error -> exit code 0) and that stdout contains only the result line.

- [ ] **Step 2: Run the test**

Run: `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "Download_VerboseLogs_GoToStderr_NotStdout"`
Expected: passes.

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests
git commit -m "test(028): assert stdout cleanliness vs stderr"
```

---

### Task 23: Update backlog 028 + close out

**Files:**
- Modify: `.claude/backlog/028-cli-download-command.md`

- [ ] **Step 1: Update acceptance criteria text and mark complete**

Replace the existing AC block:

```markdown
## Acceptance criteria

- [ ] `ahkflowapp download ahk --profile <name>` downloads the script.
- [ ] CLI supports choosing an output path or printing to stdout.
- [ ] Authentication is handled consistently (see 012).
- [ ] Unit tests for CLI download command argument handling and output behavior.
- [ ] Integration tests validate download behavior against a test API (including headers and file content).
```

With:

```markdown
## Acceptance criteria

- [x] `ahkflow download --profile <name>` downloads the script. (AC text updated from `ahkflowapp download ahk` per design spec 2026-05-08.)
- [x] `ahkflow download --all` downloads a zip of all the user's scripts.
- [x] CLI supports `-o, --output <path>` (file) and `-o -` (stdout); `--force` overrides existing files.
- [x] Authentication via MSAL device-code (backlog 029).
- [x] Profile name -> id resolved via `GET /api/v1/profiles`; case-insensitive match.
- [x] `--verbose` (recursive root option) raises Serilog minimum to Information; events still routed to stderr.
- [x] Unit tests cover BearerTokenHandler header attachment.
- [x] Integration tests cover happy path, --all, profile not found, file collision (with and without --force), mutually-exclusive args, stdout cleanliness with --verbose, server 403 ProblemDetails surfaced via stderr.

---

**Completed:** 2026-MM-DD (PR #TBD)
```

- [ ] **Step 2: Run final checks**

Run: `dotnet build --configuration Release && dotnet test --configuration Release --no-build && dotnet format --verify-no-changes`
Expected: all green.

- [ ] **Step 3: Commit and open PR**

```bash
git add .claude/backlog/028-cli-download-command.md
git commit -m "docs(028): close backlog item"
git push -u origin feature/028-cli-download
gh pr create --title "feat(028): ahkflow download command" --body "$(cat <<'EOF'
## Summary
- Adds `ahkflow download --profile <name>` and `ahkflow download --all` commands.
- Profile name → id via `/api/v1/profiles` (case-insensitive).
- Output: default file in cwd, `-o <path>`, `-o -` for stdout, `--force` to overwrite.
- Exit codes: 0 success, 1 unexpected, 2 user error, 3 not authenticated.
- Updates backlog 028 AC to reflect the renamed binary (`ahkflow`, not `ahkflowapp`).

## Test plan
- [ ] CI green
- [ ] Integration tests pass (Testcontainers SQL)
- [ ] Manual: `ahkflow download --profile Default` against TEST environment writes script
- [ ] Manual: `ahkflow download --all -o scripts.zip` writes a valid zip
- [ ] Manual: `ahkflow download --all -o -` produces zip bytes on stdout (verify with `ahkflow download --all -o - | unzip -l -`)

Spec: `docs/superpowers/specs/2026-05-08-cli-foundation-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review (run by plan author at write time, not by the engineer)

The plan author has checked the plan against the spec — gaps and fixes documented inline above. Notable items the engineer should verify, not the plan:

- **Spec coverage:** All 9 review findings from the spec review are reflected in the plan tasks (LoginResult, env var keys, slnx update, Entra Graph PATCHes, Serilog stderr, exit codes, profile resolution, etc.).
- **Stdout-byte testing for `-o -` zip:** explicitly punted to manual smoke (Task 21 Step 2). Acceptable - the mixing concern is covered by Task 22.
- **`--verbose` flag:** wired in Phase 1 via a recursive root option (`RootCli.VerboseOption`). Program.cs pre-parses `args` to set Serilog minimum to Information when present; `standardErrorFromLevel: Verbose` continues to route every event to stderr. Task 22 exercises it.
- **403 ProblemDetails surfacing:** `DownloadsApiClient.GetAsync` reads the body for non-2xx responses (when content-type is JSON or `application/problem+json`), extracts the `detail` field, and throws `HttpRequestException(detail, null, statusCode)` so `DownloadCommand` prints `Forbidden: <server detail>` to stderr.
- **xUnit collection scope:** `tests/AHKFlowApp.CLI.Tests/Collections.cs` is created in Task 18 because `[CollectionDefinition]` is per-assembly; the existing definition in `tests/AHKFlowApp.API.Tests` is not visible to the new test project.
- **CliRunner auth pipeline:** `BearerTokenHandler` is registered on the test `IServiceCollection` and added to both typed clients via `.AddHttpMessageHandler<BearerTokenHandler>()` so the not-signed-in test exercises the real auth provider path.
- **Type consistency:** `LoginResult(string Username, bool WasAlreadySignedIn)` used the same way in `IAuthTokenProvider`, `MsalDeviceCodeTokenProvider`, and `LoginCommand`. `DownloadResult(byte[] Bytes, string FileName, string ContentType)` likewise. `ProfileSummary(Guid Id, string Name)` matches the API DTO field names.

---

## Plan complete

Plan saved to `docs/superpowers/plans/2026-05-08-cli-foundation.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session via executing-plans, batched with checkpoints.

Which approach?
