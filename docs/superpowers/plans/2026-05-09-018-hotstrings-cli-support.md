# 018 — Hotstrings CLI support (create/list + JSON) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `ahkflow hotstring new` and `ahkflow hotstring list` (with `--json`) in a single PR. Replace the stubbed auth provider with one that reads `AHKFLOW_TOKEN`. Add the `IProfilesApiClient` impl that 017 deferred (also unblocks 028 download).

**Architecture:** All work lives inside `src/Tools/AHKFlowApp.CLI` and `tests/AHKFlowApp.CLI.Tests`. CLI keeps its Clean-Architecture independence — DTOs are duplicated locally as records, no reference to `AHKFlowApp.Application`. Test project gains `ProjectReference`s to `AHKFlowApp.API` (for `WebApplicationFactory<Program>`) and `AHKFlowApp.TestUtilities`.

**Tech Stack:** .NET 10, System.CommandLine 3.0 preview, `Microsoft.Extensions.Hosting`, `IHttpClientFactory` + `StandardResilienceHandler` + `BearerTokenHandler`, Serilog, xUnit + FluentAssertions + NSubstitute, Testcontainers (transitively via TestUtilities).

**Spec:** `docs/superpowers/specs/2026-05-09-018-hotstrings-cli-support-design.md`

**Branch:** `feature/018-hotstrings-cli-support` — cut from `main` after 017 has merged. Single PR.

---

## File structure (locked in by this plan)

**New files in `src/Tools/AHKFlowApp.CLI/`:**

| Path | Responsibility |
|---|---|
| `Services/EnvVarAuthTokenProvider.cs` | Reads `AHKFLOW_TOKEN`; throws `NotAuthenticatedException` if unset/empty |
| `Services/IHotstringsApiClient.cs` | Interface + local `HotstringDto`, `CreateHotstringDto`, `PagedList<T>` records |
| `Services/HotstringsApiClient.cs` | Typed `HttpClient` impl: `CreateAsync`, `ListAsync` |
| `Services/ProfilesApiClient.cs` | Typed `HttpClient` impl of existing `IProfilesApiClient` |
| `Commands/Hotstrings/HotstringCommand.cs` | Verb-noun group: `hotstring` |
| `Commands/Hotstrings/NewHotstringCommand.cs` | `ahkflow hotstring new` |
| `Commands/Hotstrings/ListHotstringCommand.cs` | `ahkflow hotstring list` |
| `Output/HotstringTableFormatter.cs` | Writes human table to `TextWriter` |
| `Output/HotstringJsonFormatter.cs` | Writes JSON to `TextWriter` via `System.Text.Json` |

**New files in `tests/AHKFlowApp.CLI.Tests/`:**

| Path | Responsibility |
|---|---|
| `Collections.cs` | `[CollectionDefinition("CliWebApi")]` + `SqlContainerFixture` |
| `Infrastructure/CliTestHost.cs` | Builds CLI `IServiceProvider` wired to `WebApplicationFactory.Server.CreateHandler()` |
| `Infrastructure/StubAuthTokenProvider.cs` | Returns canned token, or throws `NotAuthenticatedException` if `null` |
| `Services/EnvVarAuthTokenProviderTests.cs` | Unit |
| `Output/HotstringTableFormatterTests.cs` | Unit |
| `Output/HotstringJsonFormatterTests.cs` | Unit |
| `Commands/Hotstrings/NewHotstringCommandTests.cs` | Unit (NSubstitute clients) |
| `Commands/Hotstrings/ListHotstringCommandTests.cs` | Unit (NSubstitute clients) |
| `Integration/HotstringCliIntegrationTests.cs` | End-to-end via `WebApplicationFactory` + Testcontainers |

**Deleted:**
- `src/Tools/AHKFlowApp.CLI/Services/NullAuthTokenProvider.cs` (replaced by `EnvVarAuthTokenProvider`)

**Modified:**
- `src/Tools/AHKFlowApp.CLI/Program.cs` — swap auth registration, add `AddHttpClient<IHotstringsApiClient,…>` and `AddHttpClient<IProfilesApiClient,…>`
- `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs` — wire `HotstringCommand`
- `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj` — add API + TestUtilities `ProjectReference`s
- `.claude/backlog/018-hotstrings-cli-support.md` — update AC text (`ahkflow hotstring new/list`), mark complete
- `.claude/backlog/017-scaffold-cli-project.md` — note `IAuthTokenProvider` no longer stubbed
- `.claude/backlog/028-cli-download-command.md` — note Profiles client moved to 018; only download remains

---

## Task 1 — Branch and test-project wiring

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj`

- [ ] **Step 1: Cut feature branch from `main`**

```bash
git fetch origin
git switch main && git pull
git switch -c feature/018-hotstrings-cli-support
```

- [ ] **Step 2: Add `ProjectReference`s to API and TestUtilities**

Modify `tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj` so the existing `<ItemGroup>` of project references becomes:

```xml
<ItemGroup>
  <ProjectReference Include="..\..\src\Tools\AHKFlowApp.CLI\AHKFlowApp.CLI.csproj" />
  <ProjectReference Include="..\..\src\Backend\AHKFlowApp.API\AHKFlowApp.API.csproj" />
  <ProjectReference Include="..\AHKFlowApp.TestUtilities\AHKFlowApp.TestUtilities.csproj" />
</ItemGroup>
```

The API reference exposes `Program` (the `WebApplicationFactory<Program>` entry-point class). TestUtilities exposes `SqlContainerFixture`, `CustomWebApplicationFactory`, and `WithTestAuth`.

- [ ] **Step 3: Verify build**

```bash
dotnet build --configuration Release
```

Expected: succeeds. The CLI test project picks up the new references with no compile errors yet (no test files reference them).

- [ ] **Step 4: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests/AHKFlowApp.CLI.Tests.csproj
git commit -m "test(018): wire API + TestUtilities refs into CLI tests"
```

---

## Task 2 — Replace `NullAuthTokenProvider` with `EnvVarAuthTokenProvider` (TDD)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/EnvVarAuthTokenProvider.cs`
- Create: `tests/AHKFlowApp.CLI.Tests/Services/EnvVarAuthTokenProviderTests.cs`
- Delete: `src/Tools/AHKFlowApp.CLI/Services/NullAuthTokenProvider.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`

- [ ] **Step 1: Write failing tests first**

Create `tests/AHKFlowApp.CLI.Tests/Services/EnvVarAuthTokenProviderTests.cs`:

```csharp
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class EnvVarAuthTokenProviderTests
{
    private const string Var = "AHKFLOW_TOKEN";

    [Fact]
    public async Task GetTokenAsync_EnvVarSet_ReturnsToken()
    {
        using var _ = new EnvVarScope(Var, "abc.def.ghi");
        EnvVarAuthTokenProvider sut = new();

        string token = await sut.GetTokenAsync(CancellationToken.None);

        token.Should().Be("abc.def.ghi");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task GetTokenAsync_EnvVarUnsetOrBlank_ThrowsNotAuthenticated(string? value)
    {
        using var _ = new EnvVarScope(Var, value);
        EnvVarAuthTokenProvider sut = new();

        Func<Task> act = () => sut.GetTokenAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<NotAuthenticatedException>())
            .WithMessage("Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.");
    }

    [Fact]
    public async Task LoginAsync_Throws_NotImplementedForItem029()
    {
        EnvVarAuthTokenProvider sut = new();

        Func<Task> act = () => sut.LoginAsync(CancellationToken.None);

        await act.Should().ThrowAsync<NotImplementedException>();
    }

    private sealed class EnvVarScope : IDisposable
    {
        private readonly string _name;
        private readonly string? _previous;
        public EnvVarScope(string name, string? value)
        {
            _name = name;
            _previous = Environment.GetEnvironmentVariable(name);
            Environment.SetEnvironmentVariable(name, value);
        }
        public void Dispose() => Environment.SetEnvironmentVariable(_name, _previous);
    }
}
```

Run: `dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~EnvVarAuthTokenProvider"` — expect compile failure (no `EnvVarAuthTokenProvider` yet).

- [ ] **Step 2: Implement `EnvVarAuthTokenProvider`**

Create `src/Tools/AHKFlowApp.CLI/Services/EnvVarAuthTokenProvider.cs`:

```csharp
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
```

- [ ] **Step 3: Delete `NullAuthTokenProvider`**

```bash
git rm src/Tools/AHKFlowApp.CLI/Services/NullAuthTokenProvider.cs
```

- [ ] **Step 4: Update `Program.cs` registration**

In `src/Tools/AHKFlowApp.CLI/Program.cs`, replace:

```csharp
builder.Services.AddSingleton<IAuthTokenProvider, NullAuthTokenProvider>();
```

with:

```csharp
builder.Services.AddSingleton<IAuthTokenProvider, EnvVarAuthTokenProvider>();
```

- [ ] **Step 5: Run tests**

```bash
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~EnvVarAuthTokenProvider" --configuration Release
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat(018): swap NullAuthTokenProvider for EnvVarAuthTokenProvider"
```

---

## Task 3 — Hotstring DTOs + `IHotstringsApiClient`

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`

- [ ] **Step 1: Define interface and local DTOs**

```csharp
namespace AHKFlowApp.CLI.Services;

public interface IHotstringsApiClient
{
    Task<HotstringDto> CreateAsync(CreateHotstringDto input, CancellationToken ct);

    Task<PagedList<HotstringDto>> ListAsync(
        Guid? profileId,
        string? search,
        int page,
        int pageSize,
        CancellationToken ct);
}

public sealed record HotstringDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

// ProfileIds is nullable: CLI sends null when --profile is omitted (all profiles).
// API handler treats null and [] equivalently.
public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = true,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);

public sealed record PagedList<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}
```

- [ ] **Step 2: Build to confirm interface compiles**

```bash
dotnet build src/Tools/AHKFlowApp.CLI --configuration Release
```

(No commit yet — bundle with Task 4.)

---

## Task 4 — `HotstringsApiClient` impl

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/HotstringsApiClient.cs`

- [ ] **Step 1: Implement typed HttpClient**

```csharp
using System.Net.Http.Json;
using System.Text.Json;

namespace AHKFlowApp.CLI.Services;

public sealed class HotstringsApiClient(HttpClient http) : IHotstringsApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = JsonSerializerOptions.Web;

    public async Task<HotstringDto> CreateAsync(CreateHotstringDto input, CancellationToken ct)
    {
        using HttpResponseMessage response = await http.PostAsJsonAsync(
            "api/v1/hotstrings", input, JsonOptions, ct);
        response.EnsureSuccessStatusCode();
        HotstringDto dto = await response.Content.ReadFromJsonAsync<HotstringDto>(JsonOptions, ct)
            ?? throw new InvalidOperationException("API returned empty body for create hotstring.");
        return dto;
    }

    public async Task<PagedList<HotstringDto>> ListAsync(
        Guid? profileId, string? search, int page, int pageSize, CancellationToken ct)
    {
        List<string> qs = new();
        if (profileId is { } pid) qs.Add($"profileId={Uri.EscapeDataString(pid.ToString())}");
        if (!string.IsNullOrWhiteSpace(search)) qs.Add($"search={Uri.EscapeDataString(search)}");
        qs.Add($"page={page}");
        qs.Add($"pageSize={pageSize}");
        string url = $"api/v1/hotstrings?{string.Join('&', qs)}";

        using HttpResponseMessage response = await http.GetAsync(url, ct);
        response.EnsureSuccessStatusCode();
        PagedList<HotstringDto> result = await response.Content
            .ReadFromJsonAsync<PagedList<HotstringDto>>(JsonOptions, ct)
            ?? throw new InvalidOperationException("API returned empty body for list hotstrings.");
        return result;
    }
}
```

> **Note:** Error handling here is intentionally minimal — `EnsureSuccessStatusCode` throws `HttpRequestException` on non-success. Commands convert these to user-facing exit codes (Tasks 9–10) by inspecting the response status. Consider switching to manual status handling if commands need richer info — see Task 9 for the chosen approach.

- [ ] **Step 2: Build**

```bash
dotnet build src/Tools/AHKFlowApp.CLI --configuration Release
```

(No commit yet.)

---

## Task 5 — `ProfilesApiClient` impl (017's deferred work)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/ProfilesApiClient.cs`

- [ ] **Step 1: Implement typed HttpClient**

`GET /api/v1/profiles` returns `IReadOnlyList<ProfileDto>` directly (not a paged envelope) — see `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs:23`. CLI only needs `id`/`name`, so we deserialize into a small transport record and project to `ProfileSummary`:

```csharp
using System.Net.Http.Json;
using System.Text.Json;

namespace AHKFlowApp.CLI.Services;

public sealed class ProfilesApiClient(HttpClient http) : IProfilesApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = JsonSerializerOptions.Web;

    public async Task<IReadOnlyList<ProfileSummary>> ListAsync(CancellationToken ct)
    {
        using HttpResponseMessage response = await http.GetAsync("api/v1/profiles", ct);
        if (!response.IsSuccessStatusCode)
        {
            string body = await response.Content.ReadAsStringAsync(ct);
            throw new ApiException((int)response.StatusCode, body);
        }
        IReadOnlyList<ProfileItem>? items = await response.Content
            .ReadFromJsonAsync<IReadOnlyList<ProfileItem>>(JsonOptions, ct);
        if (items is null)
            throw new InvalidOperationException("API returned empty body for list profiles.");
        return items.Select(p => new ProfileSummary(p.Id, p.Name)).ToList();
    }

    private sealed record ProfileItem(Guid Id, string Name);
}
```

- [ ] **Step 2: Verify against actual API DTO**

Confirm `ProfileDto` (`src/Backend/AHKFlowApp.Application/DTOs/ProfileDto.cs`) still exposes `Id` and `Name`; the local `ProfileItem` ignores other fields. If the controller ever switches to paged output, revise this client.

```bash
dotnet build --configuration Release
```

(No commit yet.)

---

## Task 6 — Wire HttpClient registrations in `Program.cs`

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`

- [ ] **Step 1: Replace the deferral comment with real registrations**

In `Program.cs`, replace:

```csharp
// HttpClient registrations for IDownloadsApiClient and IProfilesApiClient land in backlog 028.
```

with:

```csharp
string apiBaseUrl = builder.Configuration["ApiBaseUrl"]
    ?? throw new InvalidOperationException("Configuration value 'ApiBaseUrl' is required.");

builder.Services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

builder.Services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

// IDownloadsApiClient registration lands with backlog 028.
```

- [ ] **Step 2: Build + smoke `--help`**

```bash
dotnet build --configuration Release
dotnet run --project src/Tools/AHKFlowApp.CLI --configuration Release -- --help
```

Expected: help renders (still no subcommands shown — those land in Task 12).

- [ ] **Step 3: Commit Tasks 3–6 together**

```bash
git add src/Tools/AHKFlowApp.CLI
git commit -m "feat(018): hotstrings + profiles api clients"
```

---

## Task 7 — `HotstringJsonFormatter` (TDD)

**Files:**
- Create: `tests/AHKFlowApp.CLI.Tests/Output/HotstringJsonFormatterTests.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Output/HotstringJsonFormatter.cs`

- [ ] **Step 1: Write failing tests**

```csharp
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Output;

public sealed class HotstringJsonFormatterTests
{
    [Fact]
    public void WriteSingle_EmitsCamelCaseIndentedJson()
    {
        var dto = new HotstringDto(
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            [],
            true,
            "btw",
            "by the way",
            true,
            true,
            new DateTimeOffset(2026, 5, 8, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 5, 8, 12, 0, 0, TimeSpan.Zero));

        StringWriter sw = new();
        HotstringJsonFormatter.WriteSingle(sw, dto);

        string output = sw.ToString();
        output.Should().Contain("\"appliesToAllProfiles\": true");
        output.Should().Contain("\"trigger\": \"btw\"");
        output.Should().Contain("\n"); // indented
    }

    [Fact]
    public void WritePage_RoundtripsToPagedList()
    {
        var page = new PagedList<HotstringDto>(
            [],
            Page: 1,
            PageSize: 50,
            TotalCount: 0);

        StringWriter sw = new();
        HotstringJsonFormatter.WritePage(sw, page);

        var roundtrip = System.Text.Json.JsonSerializer.Deserialize<PagedList<HotstringDto>>(
            sw.ToString(), System.Text.Json.JsonSerializerOptions.Web);
        roundtrip.Should().NotBeNull();
        roundtrip!.TotalCount.Should().Be(0);
    }
}
```

- [ ] **Step 2: Implement formatter**

```csharp
using System.Text.Json;
using AHKFlowApp.CLI.Services;

namespace AHKFlowApp.CLI.Output;

public static class HotstringJsonFormatter
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerOptions.Web)
    {
        WriteIndented = true,
    };

    public static void WriteSingle(TextWriter writer, HotstringDto dto)
    {
        writer.WriteLine(JsonSerializer.Serialize(dto, Options));
    }

    public static void WritePage(TextWriter writer, PagedList<HotstringDto> page)
    {
        writer.WriteLine(JsonSerializer.Serialize(page, Options));
    }
}
```

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~HotstringJsonFormatter" --configuration Release
```

Expected: 2 pass. (No commit — bundle with Task 8.)

---

## Task 8 — `HotstringTableFormatter` (TDD)

**Files:**
- Create: `tests/AHKFlowApp.CLI.Tests/Output/HotstringTableFormatterTests.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Output/HotstringTableFormatter.cs`

- [ ] **Step 1: Write failing tests**

Cover (one test per case): empty page → "No hotstrings found.", `AppliesToAllProfiles=true` → "all", profile names resolved (3 profiles), `+N more` (5 profiles), `Profiles` truncation when string > 24 chars, long trigger truncation with `…`, footer hidden when `TotalPages <= 1`, footer shown when `TotalPages > 1`, `Updated` formatted as `yyyy-MM-dd HH:mm:ss` local.

Use `StringWriter` to capture; assert with `Should().Contain(...)`/`Should().NotContain(...)`.

- [ ] **Step 2: Implement formatter**

Public API:

```csharp
public static class HotstringTableFormatter
{
    public static void Write(
        TextWriter writer,
        PagedList<HotstringDto> page,
        IReadOnlyDictionary<Guid, string> profileNamesById);
}
```

Rules from spec:
- Columns: `Trigger` ≤20, `Replacement` ≤40, `Profiles` ≤24, `Updated` =19 (fixed).
- Truncate with `…`. `Updated` never truncated.
- `Updated` = `dto.UpdatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")`.
- `Profiles` = `"all"` if `AppliesToAllProfiles`; else first 3 names joined by `", "`; if > 3 append ` +N more`. Unresolved IDs → `<n> profiles` fallback.
- Empty `Items` → `"No hotstrings found."` only, no header, no footer.
- Footer (`Page X/Y (showing M of T) — use --page N for next`) only when `TotalPages > 1`.

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~HotstringTableFormatter" --configuration Release
```

Expected: all formatter tests pass.

- [ ] **Step 4: Commit Tasks 7–8 together**

```bash
git add src tests
git commit -m "feat(018): hotstring table + json formatters"
```

---

## Task 9 — `NewHotstringCommand` (impl + unit tests)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/HotstringCommand.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/NewHotstringCommand.cs`
- Create: `tests/AHKFlowApp.CLI.Tests/Infrastructure/CliTestHost.cs`
- Create: `tests/AHKFlowApp.CLI.Tests/Infrastructure/StubAuthTokenProvider.cs`
- Create: `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/NewHotstringCommandTests.cs`

- [ ] **Step 1: `HotstringCommand` group**

```csharp
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class HotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("hotstring", "Manage hotstrings.")
        {
            NewHotstringCommand.Build(services),
            ListHotstringCommand.Build(services),
        };
        return cmd;
    }
}
```

(The `ListHotstringCommand` reference resolves once Task 10 lands — fine to add now and let the build break temporarily, or stub a placeholder until Task 10. Prefer placeholder so the test loop stays green.)

- [ ] **Step 2: `StubAuthTokenProvider` test helper**

```csharp
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
```

- [ ] **Step 3: `CliTestHost` (in-memory wiring helper)**

For *unit* tests we don't need the real API factory — we register `NSubstitute.For<IHotstringsApiClient>()` directly. For the *integration* tests (Task 13) we use this builder with a real `WebApplicationFactory`. Both modes share the helper — give it overloads:

```csharp
using AHKFlowApp.API; // for the Program type
using AHKFlowApp.CLI.Services;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Tests.Infrastructure;

internal static class CliTestHost
{
    // For unit tests: caller supplies fake clients.
    public static IServiceProvider WithFakes(
        IHotstringsApiClient hotstrings,
        IProfilesApiClient profiles,
        IAuthTokenProvider? auth = null)
    {
        ServiceCollection services = new();
        services.AddSingleton(hotstrings);
        services.AddSingleton(profiles);
        services.AddSingleton(auth ?? new StubAuthTokenProvider("test-token"));
        return services.BuildServiceProvider();
    }

    // For integration tests: typed clients backed by the in-memory API.
    public static IServiceProvider WithFactory(
        WebApplicationFactory<Program> factory,
        string? token = "test-token")
    {
        ServiceCollection services = new();
        services.AddSingleton<IAuthTokenProvider>(new StubAuthTokenProvider(token));
        services.AddTransient<BearerTokenHandler>();

        services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();

        services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();

        return services.BuildServiceProvider();
    }
}
```

- [ ] **Step 4: `NewHotstringCommand` impl**

Behavior reference: spec section "ahkflow hotstring new". Key points:
- Required options `-t/--trigger`, `-r/--replacement`. Optional `-p/--profile` (multi-valued), `--no-ending-char`, `--no-inside-word`, `--json`.
- **Defaults align with API/UI:** `IsEndingCharacterRequired=true`, `IsTriggerInsideWord=true` (see `CreateHotstringDto` defaults at `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs:14` and UI at `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs:20`). The CLI uses `--no-*` opt-outs to match: omitting both flags sends `true/true`. **The spec table at line 93 of the design doc lists `--inside-word` defaulting `true` — that's the same intent expressed differently; this plan locks in `--no-inside-word`.**
- If any `--profile` supplied: call `IProfilesApiClient.ListAsync`, build `Dictionary<string, Guid>` keyed by name with `StringComparer.OrdinalIgnoreCase`, resolve each input. Unknown name → write `Profile '<name>' not found. Available: A, B, C` to stderr, return `2`.
- If no `--profile` supplied: send `ProfileIds = null`, `AppliesToAllProfiles = true`.
- Catch `NotAuthenticatedException` → stderr message, return `3`.
- Catch `ApiException` and inspect `StatusCode`:
  - `400` / `409` → write response body (ProblemDetails) to stderr, return `2`.
  - `401` / `403` → stderr `"Not signed in…"`, return `3`. (`403` happens when the bearer token is missing the `access_as_user` scope — see `[RequiredScope]` at `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs:16` and the equivalent on `HotstringsController`.)
  - `5xx` or null → stderr (body if present, else `"Server error"`), return `1`.
- Catch `HttpRequestException` (transport failure) → stderr `ex.Message`, return `1`.
- Success → `Created hotstring <id> ('<trigger>')` to stdout (or full DTO JSON if `--json`), return `0`.

> `HttpClient.PostAsJsonAsync` followed by `EnsureSuccessStatusCode` is too coarse for this — switch the inner client method to return `HttpResponseMessage` *or* read the body before throwing. Recommended: change `HotstringsApiClient.CreateAsync` to throw a custom `ApiException(int status, string? body)`. Add this type in `Services/ApiException.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public sealed class ApiException(int statusCode, string? body)
    : Exception($"API returned {statusCode}.")
{
    public int StatusCode { get; } = statusCode;
    public string? Body { get; } = body;
}
```

Update `HotstringsApiClient.CreateAsync` and `ListAsync` to throw `ApiException` on non-success:

```csharp
if (!response.IsSuccessStatusCode)
{
    string body = await response.Content.ReadAsStringAsync(ct);
    throw new ApiException((int)response.StatusCode, body);
}
```

Add the same to `ProfilesApiClient.ListAsync`.

Skeleton for `NewHotstringCommand.Build`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class NewHotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string> trigger = new("--trigger", "-t") { Description = "Abbreviation to expand.", Required = true };
        Option<string> replacement = new("--replacement", "-r") { Description = "Replacement text.", Required = true };
        Option<string[]> profile = new("--profile", "-p") { Description = "Profile name (repeatable)." };
        Option<bool> noEndingChar = new("--no-ending-char") { Description = "Don't require an ending character (default: required)." };
        Option<bool> noInsideWord = new("--no-inside-word") { Description = "Don't trigger inside words (default: triggers inside words)." };
        Option<bool> json = new("--json") { Description = "Emit JSON instead of human summary." };

        Command cmd = new("new", "Create a new hotstring.")
        {
            trigger, replacement, profile, noEndingChar, noInsideWord, json,
        };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IHotstringsApiClient hotstrings = services.GetRequiredService<IHotstringsApiClient>();
            IProfilesApiClient profiles = services.GetRequiredService<IProfilesApiClient>();

            try
            {
                Guid[]? resolvedIds = null;
                bool appliesToAll = true;
                string[]? names = parse.GetValue(profile);
                if (names is { Length: > 0 })
                {
                    IReadOnlyList<ProfileSummary> all = await profiles.ListAsync(ct);
                    Dictionary<string, Guid> byName = new(StringComparer.OrdinalIgnoreCase);
                    foreach (ProfileSummary p in all) byName[p.Name] = p.Id;
                    List<Guid> resolved = [];
                    foreach (string n in names)
                    {
                        if (!byName.TryGetValue(n, out Guid id))
                        {
                            string available = string.Join(", ", all.Select(a => a.Name));
                            await stderr.WriteLineAsync($"Profile '{n}' not found. Available: {available}");
                            return 2;
                        }
                        resolved.Add(id);
                    }
                    resolvedIds = [.. resolved];
                    appliesToAll = false;
                }

                CreateHotstringDto input = new(
                    Trigger: parse.GetValue(trigger)!,
                    Replacement: parse.GetValue(replacement)!,
                    ProfileIds: resolvedIds,
                    AppliesToAllProfiles: appliesToAll,
                    IsEndingCharacterRequired: !parse.GetValue(noEndingChar),
                    IsTriggerInsideWord: !parse.GetValue(noInsideWord));

                HotstringDto created = await hotstrings.CreateAsync(input, ct);

                if (parse.GetValue(json))
                    HotstringJsonFormatter.WriteSingle(stdout, created);
                else
                    await stdout.WriteLineAsync(
                        $"Created hotstring {created.Id} ('{created.Trigger}')");
                return 0;
            }
            catch (NotAuthenticatedException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 3;
            }
            catch (ApiException ex) when (ex.StatusCode is 400 or 409)
            {
                await stderr.WriteLineAsync(ex.Body ?? ex.Message);
                return 2;
            }
            catch (ApiException ex) when (ex.StatusCode is 401 or 403)
            {
                await stderr.WriteLineAsync(
                    "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.");
                return 3;
            }
            catch (ApiException ex)
            {
                await stderr.WriteLineAsync(ex.Body ?? $"Server error ({ex.StatusCode}).");
                return 1;
            }
            catch (HttpRequestException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 5: Unit tests**

Cover (per spec test list):
- `--profile` omitted → `CreateAsync` called with `ProfileIds=null`, `AppliesToAllProfiles=true`. Asserted via `NSubstitute.Received().CreateAsync(Arg.Is<CreateHotstringDto>(d => d.ProfileIds == null && d.AppliesToAllProfiles))`.
- Two `--profile` flags → resolved to `[guid1, guid2]`, `AppliesToAllProfiles=false`.
- Mixed-case profile name (`--profile WORK`) resolves to lowercase entry.
- Unknown profile → exit 2, stderr starts with `"Profile 'nope' not found. Available: "`.
- Defaults (no `--no-*` flags) → `IsEndingCharacterRequired=true` AND `IsTriggerInsideWord=true`.
- `--no-ending-char` → `IsEndingCharacterRequired=false`.
- `--no-inside-word` → `IsTriggerInsideWord=false`.
- `--json` → stdout starts with `{`; otherwise `"Created hotstring "`.
- API throws `ApiException(400|409)` → stderr non-empty, exit 2.
- API throws `ApiException(401)` → exit 3, stderr `"Not signed in…"`.
- API throws `ApiException(403)` (missing scope) → exit 3, stderr `"Not signed in…"`.
- API throws `ApiException(500)` → exit 1.
- API throws `HttpRequestException` (network failure) → exit 1.
- Success → exit 0.

> **Note on auth:** Don't test `NotAuthenticatedException` here by passing `StubAuthTokenProvider(null)` to `CliTestHost.WithFakes`. The fake `IHotstringsApiClient` skips the HTTP pipeline entirely, so the auth provider is never consulted — the test would pass for the wrong reason. Cover that path by configuring the **fake** API client to throw `NotAuthenticatedException`, and leave provider-level behavior to `EnvVarAuthTokenProviderTests` (Task 2) and integration test #13 (Task 12).

Capture pattern (re-used in every test):

```csharp
StringWriter stdout = new();
StringWriter stderr = new();
RootCommand root = new() { HotstringCommand.Build(services) };
int exit = await root.Parse(args)
    .InvokeAsync(new InvocationConfiguration { Output = stdout, Error = stderr });
```

- [ ] **Step 6: Run tests**

```bash
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~NewHotstringCommand" --configuration Release
```

Expected: all pass.

(No commit — bundle with Task 10.)

---

## Task 10 — `ListHotstringCommand` (impl + unit tests)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs`
- Create: `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs`

- [ ] **Step 1: Implement command**

Behavior reference: spec section "ahkflow hotstring list". Key points:
- Options: `-p/--profile` (single, optional), `-s/--search`, `--page` (default 1), `--page-size` (default 50), `--json`.
- **Profiles fetch is conditional** (perf): call `IProfilesApiClient.ListAsync` only when needed:
  - `--profile` is set (need name→id resolution), OR
  - `--json` is **not** set (need id→name map for table column rendering).
  - When `--json` is set AND `--profile` is omitted: skip the round-trip entirely. JSON output doesn't surface profile names, so name resolution adds latency and a failure point for nothing.
- If `--profile` set: resolve to GUID via `IProfilesApiClient` (case-insensitive). Unknown → stderr `Profile '<name>' not found. Available: …`, exit 2.
- Call `hotstrings.ListAsync(profileId, search, page, pageSize, ct)`.
- `--json` → `HotstringJsonFormatter.WritePage(stdout, page)`. Else `HotstringTableFormatter.Write(stdout, page, idToNameMap)`.
- Error mapping identical to `NewHotstringCommand` (`ApiException` 400/409 → 2; 401/403 → 3; 5xx/null → 1; `NotAuthenticatedException` → 3; `HttpRequestException` → 1).
- Empty page is *not* an error — formatter writes `"No hotstrings found."`, exit 0.

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Hotstrings;

public static class ListHotstringCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string?> profile = new("--profile", "-p") { Description = "Filter by profile name." };
        Option<string?> search = new("--search", "-s") { Description = "Search trigger / replacement." };
        Option<int> page = new("--page") { Description = "Page (1-indexed).", DefaultValueFactory = _ => 1 };
        Option<int> pageSize = new("--page-size") { Description = "Items per page (1-200).", DefaultValueFactory = _ => 50 };
        Option<bool> json = new("--json") { Description = "Emit JSON instead of human table." };

        Command cmd = new("list", "List hotstrings.") { profile, search, page, pageSize, json };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IHotstringsApiClient hotstrings = services.GetRequiredService<IHotstringsApiClient>();
            IProfilesApiClient profilesClient = services.GetRequiredService<IProfilesApiClient>();

            string? profileName = parse.GetValue(profile);
            bool wantJson = parse.GetValue(json);
            bool needsProfiles = profileName is not null || !wantJson;

            try
            {
                Guid? profileId = null;
                IReadOnlyDictionary<Guid, string> idToName =
                    System.Collections.Frozen.FrozenDictionary<Guid, string>.Empty;

                if (needsProfiles)
                {
                    IReadOnlyList<ProfileSummary> all = await profilesClient.ListAsync(ct);
                    idToName = all.ToDictionary(p => p.Id, p => p.Name);

                    if (profileName is not null)
                    {
                        ProfileSummary? match = all.FirstOrDefault(p =>
                            string.Equals(p.Name, profileName, StringComparison.OrdinalIgnoreCase));
                        if (match is null)
                        {
                            string available = string.Join(", ", all.Select(a => a.Name));
                            await stderr.WriteLineAsync(
                                $"Profile '{profileName}' not found. Available: {available}");
                            return 2;
                        }
                        profileId = match.Id;
                    }
                }

                PagedList<HotstringDto> result = await hotstrings.ListAsync(
                    profileId,
                    parse.GetValue(search),
                    parse.GetValue(page),
                    parse.GetValue(pageSize),
                    ct);

                if (wantJson)
                    HotstringJsonFormatter.WritePage(stdout, result);
                else
                    HotstringTableFormatter.Write(stdout, result, idToName);
                return 0;
            }
            catch (NotAuthenticatedException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 3;
            }
            catch (ApiException ex) when (ex.StatusCode is 400 or 409)
            {
                await stderr.WriteLineAsync(ex.Body ?? ex.Message);
                return 2;
            }
            catch (ApiException ex) when (ex.StatusCode is 401 or 403)
            {
                await stderr.WriteLineAsync(
                    "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.");
                return 3;
            }
            catch (ApiException ex)
            {
                await stderr.WriteLineAsync(ex.Body ?? $"Server error ({ex.StatusCode}).");
                return 1;
            }
            catch (HttpRequestException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 2: Unit tests**

Cover (per spec):
- `--page 2 --page-size 25` → `ListAsync` called with `(null, null, 2, 25)`.
- `--profile work` → `ListAsync` called with first arg `=workGuid`.
- `--profile WORK` → still resolves (case-insensitive).
- `--search btw` → `ListAsync` called with `search="btw"`.
- `--json` → stdout starts with `{`.
- Default → table header present.
- Unknown profile → exit 2, stderr correct.
- API `ApiException(400)` → exit 2.
- API `ApiException(401)` → exit 3.
- API `ApiException(403)` (missing scope) → exit 3.
- API `ApiException(500)` → exit 1.
- API `HttpRequestException` (network) → exit 1.
- Empty page → stdout contains `"No hotstrings found."`, exit 0.
- Success → exit 0.
- **Profile fetch optimization (one assertion per case):**
  - `--json` with no `--profile` → `IProfilesApiClient.ListAsync` is **never** called (`profilesClient.DidNotReceive().ListAsync(default!)`).
  - `--json --profile work` → `ListAsync` **is** called (need to resolve name).
  - No `--json`, no `--profile` → `ListAsync` **is** called (need name map for table).

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release
```

Expected: all unit tests green.

- [ ] **Step 4: Commit Tasks 9–10**

```bash
git add src tests
git commit -m "feat(018): hotstring new + list commands"
```

---

## Task 11 — Wire commands into `RootCli`

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`

- [ ] **Step 1: Add subcommand**

```csharp
using AHKFlowApp.CLI.Commands.Hotstrings;
// ...
public static RootCommand Build(IServiceProvider services)
{
    RootCommand root = new("ahkflow - AHKFlowApp CLI")
    {
        VerboseOption,
        HotstringCommand.Build(services),
    };
    return root;
}
```

- [ ] **Step 2: Manual smoke**

```bash
dotnet run --project src/Tools/AHKFlowApp.CLI --configuration Release -- --help
dotnet run --project src/Tools/AHKFlowApp.CLI --configuration Release -- hotstring --help
dotnet run --project src/Tools/AHKFlowApp.CLI --configuration Release -- hotstring new --help
```

Expected: all three render help with expected option lists. No subcommand actually fires the API (env var unset → exit 3 if invoked).

- [ ] **Step 3: Commit**

```bash
git add src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs
git commit -m "feat(018): register hotstring command on root"
```

---

## Task 12 — Integration tests

**Files:**
- Create: `tests/AHKFlowApp.CLI.Tests/Collections.cs`
- Create: `tests/AHKFlowApp.CLI.Tests/Integration/HotstringCliIntegrationTests.cs`

- [ ] **Step 1: Collection definition**

```csharp
using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.CLI.Tests;

[CollectionDefinition("CliWebApi")]
public sealed class CliWebApiCollection : ICollectionFixture<SqlContainerFixture>;
```

- [ ] **Step 2: Test class scaffold**

```csharp
[Collection("CliWebApi")]
public sealed class HotstringCliIntegrationTests(SqlContainerFixture sql) : IAsyncLifetime
{
    // CustomWebApplicationFactory.WithTestAuth(...) returns the base WebApplicationFactory<Program>,
    // not the derived type — see tests/AHKFlowApp.TestUtilities/Fixtures/CustomWebApplicationFactory.cs:42.
    // We hold onto the base reference for HTTP handler creation; the derived instance is owned by the
    // factory chain and disposed transitively.
    private WebApplicationFactory<Program> _factory = null!;
    private CustomWebApplicationFactory _baseFactory = null!;
    private Guid _testUserOid = Guid.NewGuid();

    public Task InitializeAsync()
    {
        _baseFactory = new CustomWebApplicationFactory(sql);
        _factory = _baseFactory.WithTestAuth(u => u.WithOid(_testUserOid).WithEmail("test@example.com"));
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
        await _baseFactory.DisposeAsync();
    }

    private async Task<(int exit, string stdout, string stderr)> RunAsync(
        string[] args, string? token = "test-token")
    {
        IServiceProvider services = CliTestHost.WithFactory(_factory, token);
        StringWriter so = new(), se = new();
        RootCommand root = new() { HotstringCommand.Build(services) };
        int exit = await root.Parse(args)
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    // ... tests below
}
```

- [ ] **Step 3: Test cases (16 from spec § Integration test cases + scope test)**

Implement each as a `[Fact]`. For database seeding use the existing `ProfileBuilder`/`HotstringBuilder` test data builders from `AHKFlowApp.TestUtilities/Builders`. Reach into the factory's `IServiceScope` for `AppDbContext` to seed/assert directly. Match exit codes and stdout/stderr substrings exactly as listed in the spec.

Critical cases that catch the most regressions:
1. Happy path create — DB row exists, exit 0.
2. Happy path list — table contains seeded triggers.
3. Create with `--profile work` — junction row exists for the profile id.
4. Create with no `--profile` — persisted hotstring has `AppliesToAllProfiles=true`, no junction rows.
5. List filtered by profile — filtered correctly.
6. Case-insensitive `--profile WORK`.
7. Duplicate trigger → exit 2.
8. Unknown profile → exit 2 + stderr "Available: …".
9. Validation 400 (`-t "" -r ""`) → exit 2.
10. JSON output — `JsonSerializer.Deserialize<PagedList<HotstringDto>>` succeeds. Also assert: `list --json` (no `--profile`) does **not** request `GET /api/v1/profiles` (count requests via a counting `DelegatingHandler` between `BearerTokenHandler` and the in-memory transport).
11. Pagination — second page items.
12. Search — filter applied.
13. Auth env-unset (`StubAuthTokenProvider(null)`) → exit 3.
14. Auth 401 (configure factory test auth to reject) → exit 3.
15. Server 5xx (delegating handler that throws on POST) → exit 1.
16. **Missing scope (403)** — configure `WithTestAuth` so the principal lacks the `access_as_user` scope (`[RequiredScope]` on the controllers will then return 403). Expect exit 3 and `"Not signed in…"` to stderr. If `TestUserBuilder` doesn't expose a "without scope" path, add `WithoutScope()` to `AHKFlowApp.TestUtilities/Auth/TestUserBuilder.cs` rather than baking it into the test class.

For (14)–(16), use the `WithTestAuth` and `Server.CreateHandler()` extension points already present in `CustomWebApplicationFactory`. If a needed seam is missing, add it to `AHKFlowApp.TestUtilities` rather than baking it into the test class.

- [ ] **Step 4: Run all tests**

```bash
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release
```

Expected: all unit + integration tests green. First run will be slow (Testcontainers SQL Server pull + start).

- [ ] **Step 5: Commit**

```bash
git add tests/AHKFlowApp.CLI.Tests
git commit -m "test(018): integration coverage for hotstring CLI"
```

---

## Task 13 — Backlog + docs cleanup

**Files:**
- Modify: `.claude/backlog/018-hotstrings-cli-support.md`
- Modify: `.claude/backlog/017-scaffold-cli-project.md`
- Modify: `.claude/backlog/028-cli-download-command.md`

- [ ] **Step 1: Update 018 acceptance criteria**

Replace `ahkflowapp new` / `ahkflowapp list` with `ahkflow hotstring new` / `ahkflow hotstring list`. Tick all ACs. Add `**Completed:** 2026-05-09 (PR #NN)` line.

- [ ] **Step 2: Update 017 notes**

Append a line under "Notes / dependencies": `IAuthTokenProvider` registration is no longer stubbed — `EnvVarAuthTokenProvider` (item 018) reads `AHKFLOW_TOKEN`. Item 029 will swap in MSAL device-code provider.

- [ ] **Step 3: Update 028 notes**

Note that `IProfilesApiClient` registration + impl moved to 018; remaining 028 scope: `ahkflow download ahk` command + bulk zip (027). Update AC text from `ahkflowapp download ahk` to `ahkflow download ahk`.

- [ ] **Step 4: Commit**

```bash
git add .claude/backlog
git commit -m "docs(018): close backlog 018; update 017/028 notes"
```

---

## Task 14 — CI smoke + PR

- [ ] **Step 1: Run full build + test locally**

```bash
dotnet build --configuration Release
dotnet test --configuration Release --no-build
dotnet format --verify-no-changes
```

All three must succeed before pushing.

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin feature/018-hotstrings-cli-support
gh pr create --title "feat(018): hotstring CLI create + list commands" --body "$(cat <<'EOF'
## Summary
- Adds `ahkflow hotstring new` and `ahkflow hotstring list` (with `--json`).
- Replaces `NullAuthTokenProvider` with `EnvVarAuthTokenProvider` (reads `AHKFLOW_TOKEN`).
- Implements `IProfilesApiClient` (deferred from 017); registers typed HttpClient pipeline for hotstrings + profiles.

## Test plan
- [ ] `dotnet test` green (unit + integration).
- [ ] `ahkflow --help`, `ahkflow hotstring --help`, `ahkflow hotstring new --help` render correctly.
- [ ] Manual: against a running TEST API with a valid token, create + list hotstrings, both human + `--json`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Watch CI**

```bash
gh pr checks --watch
```

If the existing `ci.yml` smoke step (017's `ahkflow --help`) needs extending to hit `hotstring --help`, do that in a follow-up commit on the same branch.

---

## Verification matrix

| Acceptance criterion (018) | Where verified |
|---|---|
| `ahkflow hotstring new` creates a hotstring | Task 12, integration tests #1, #3, #4 |
| `ahkflow hotstring list` lists hotstrings | Task 12, integration tests #2, #5, #11, #12 |
| `--json` emits structured JSON | Task 7 unit + Task 12 #10 |
| CLI uses same contracts + validation as API | Task 12 #7 (409), #9 (400) |
| Unit tests cover parsing, handlers, formatting | Tasks 7, 8, 9, 10 |
| Integration tests validate end-to-end | Task 12 (15 cases) |

---

## Unresolved questions

- `ApiException` int status vs `Ardalis.Result` enum? (plan: int)
- `--profile` on `list` repeatable or single? (plan: single)
- `--page-size` cap (200) — CLI-side or rely on API 400? (plan: API)
- Add `ahkflow hotstring --help` smoke to `ci.yml` this PR or follow-up?
- Test `-v` verbose path?
- Update spec § "ahkflow hotstring new" flag table to rename `--inside-word` → `--no-inside-word`, or leave the spec as-is and document the divergence in commit msg?
