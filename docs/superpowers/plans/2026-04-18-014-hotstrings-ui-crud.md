# Hotstrings UI CRUD (Backlog 014) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Blazor WebAssembly UI that lets the authenticated user list, create, edit, and delete their hotstrings via the existing `/api/v1/hotstrings` API (backlog 013).

**Architecture:** New `Pages/Hotstrings.razor` with a MudTable using **inline row editing** (MudTable's `RowEditingTemplate`, `CommitEditTooltip`, `CanCancelEdit="true"`). Adding inserts a draft row at the top in edit mode; editing toggles a row in place; deleting opens a `MudMessageBox` confirmation. CRUD calls go through a new typed client `IHotstringsApiClient` registered alongside the existing `IAhkFlowAppApiHttpClient`. Validation mirrors the backend FluentValidation rules client-side; backend errors (400/404/409) surface via `ISnackbar`.

**Tech Stack:** Blazor WASM, MudBlazor 9.x (MudTable + MudMessageBox + MudSnackbar), MSAL (already wired), bUnit + xUnit + NSubstitute + FluentAssertions for unit tests, Microsoft.Playwright + xUnit for E2E.

---

## Context

Backlog 013 shipped the Hotstrings REST API (PR #70, merge `385063b`): `GET/POST/PUT/DELETE /api/v1/hotstrings` returning `HotstringDto` records, with FluentValidation, RFC 9457 error responses, and MSAL auth via `[Authorize] + [RequiredScope("access_as_user")]`. The Blazor frontend currently has only Home + Health pages — no domain features yet. Backlog 014 closes that gap so users can manage their hotstrings end-to-end without touching the API directly.

**Profile scope (014 vs 024):** The Profile entity does not exist yet (it's backlog 024). The API treats `ProfileId` as an optional `Guid?` and filters lists by `OwnerOid` (current user). For 014 we list **all** of the user's hotstrings (no profile filter) and expose `ProfileId` as an optional Guid input on create/edit. Backlog 024 will retrofit a profile picker.

**Form pattern decision:** The frontend `CLAUDE.md` previously said "use `IDialogService.ShowAsync<T>` for create/edit forms". For tabular CRUD with a small field set, inline row editing is a better fit — it matches the legacy MAUI UX, keeps the user in context, and avoids modal overhead per row. The convention is being softened in Task 8 to allow inline editing for simple tabular data; dialogs remain the right choice for complex forms.

**New convention introduced:** `ApiResult<T>` — a discriminated-status return type used by the new `IHotstringsApiClient`. The existing `IAhkFlowAppApiHttpClient` returns `T?` and throws on unexpected status; that is fine for a single read (Health) but unusable for CRUD where 400/404/409 each need different UI treatment. `ApiResult<T>` (with `ApiResultStatus` enum + `ApiProblemDetails` payload) becomes the project convention for typed clients of CRUD endpoints. The legacy client stays as-is for now; future typed clients (profiles, hotkeys) should adopt `ApiResult<T>`.

**E2E:** The bUnit project covers component behaviour with mocked HTTP. A new `tests/AHKFlowApp.E2E.Tests` Playwright project drives the **real Blazor SPA in a headless browser** against a Testcontainers-backed API (create → list → edit → delete). MSAL is bypassed via a conditional `TestAuthenticationProvider` compiled into a Blazor `Test` build, plus a Kestrel host that serves the published `wwwroot` and proxies `/api/*` to the in-process API.

---

## File Structure

**New (Frontend):**
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringDto.cs` — record mirroring backend response
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotstringDto.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotstringDto.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/PagedList.cs` — generic record matching backend shape
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/ApiProblemDetails.cs` — RFC 9457 ProblemDetails shape with `errors` map
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs`
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/ApiErrorMessageFactory.cs` — maps `ApiProblemDetails` → user-readable string
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` — page + code-behind in one file
- `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs` — edit-model with DataAnnotations for MudForm validation

**Modified (Frontend):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` — register `IHotstringsApiClient`
- `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor` — add "Hotstrings" link
- `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` — soften dialog convention

**New (Tests — bUnit):**
- `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Services/ApiErrorMessageFactoryTests.cs`
- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`

**New (Frontend Test-only auth — compiled in `Test` build only):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Auth/TestAuthenticationProvider.cs` — `AuthenticationStateProvider` returning a fixed claims principal; registered only when `appsettings.json` flag `Auth:UseTestProvider == true`
- `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.E2E.json` — sets `Auth:UseTestProvider = true` and points API base URL at the test host
- Modify `Program.cs` to register `TestAuthenticationProvider` when flag is set (replaces MSAL pipeline)

**New (Tests — E2E, Playwright UI driving):**
- `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`
- `tests/AHKFlowApp.E2E.Tests/Fixtures/ApiFactory.cs` — `WebApplicationFactory<Program>` that swaps MSAL for `TestAuthHandler`, boots Testcontainers SQL, applies migrations
- `tests/AHKFlowApp.E2E.Tests/Fixtures/TestAuthHandler.cs` — backend auth scheme that issues a synthetic principal with fixed `OwnerOid`
- `tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs` — Kestrel host serving `wwwroot` (published Blazor with `appsettings.E2E.json`) and reverse-proxying `/api/*` to `ApiFactory`'s in-process server
- `tests/AHKFlowApp.E2E.Tests/Fixtures/StackFixture.cs` — `IAsyncLifetime` orchestrating: SQL container → API → SpaHost → Playwright browser, exposing `BaseUrl` + `IPage` factory
- `tests/AHKFlowApp.E2E.Tests/Fixtures/PlaywrightInstaller.cs` — runs `Microsoft.Playwright.Program.Main(["install", "chromium"])` once per test run
- `tests/AHKFlowApp.E2E.Tests/HotstringsCrudFlowTests.cs` — Playwright-driven create/edit/delete/duplicate-409

**Modified (Solution):**
- `AHKFlowApp.sln` — add E2E test project
- `Directory.Packages.props` — add `Microsoft.Playwright`, `Microsoft.AspNetCore.Mvc.Testing`, `Yarp.ReverseProxy`

---

## Task 1: Frontend DTOs

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringDto.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotstringDto.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotstringDto.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/PagedList.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/ApiProblemDetails.cs`

- [ ] **Step 1: Create the DTO files**

```csharp
// HotstringDto.cs
namespace AHKFlowApp.UI.Blazor.DTOs;
public sealed record HotstringDto(
    Guid Id,
    Guid? ProfileId,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
```

```csharp
// CreateHotstringDto.cs
namespace AHKFlowApp.UI.Blazor.DTOs;
public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid? ProfileId = null,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);
```

```csharp
// UpdateHotstringDto.cs
namespace AHKFlowApp.UI.Blazor.DTOs;
public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid? ProfileId,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord);
```

```csharp
// PagedList.cs
namespace AHKFlowApp.UI.Blazor.DTOs;
public sealed record PagedList<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages,
    bool HasNextPage,
    bool HasPreviousPage);
```

```csharp
// ApiProblemDetails.cs
namespace AHKFlowApp.UI.Blazor.DTOs;
public sealed record ApiProblemDetails(
    string? Type,
    string? Title,
    int? Status,
    string? Detail,
    string? Instance,
    IReadOnlyDictionary<string, string[]>? Errors);
```

- [ ] **Step 2: Build the project to ensure DTOs compile**

Run: `dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/
git commit -m "feat(ui): add hotstring DTOs and ApiProblemDetails"
```

---

## Task 2: Typed HTTP Client — Interface and Implementation

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotstringsApiClient.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs`

> **Note — new project convention being introduced here:** `ApiResult<T>` + `ApiResultStatus` are **new types** in this project. The legacy `IAhkFlowAppApiHttpClient` returns `T?` and lets exceptions surface — fine for a single read on a public health endpoint, but unworkable for CRUD where 400/404/409/network each need different UI treatment. From this PR forward, typed clients for CRUD endpoints return `ApiResult<T>`. Don't generalise the legacy client — leave it alone; subsequent backlog items (profiles 024, hotkeys 016+) will adopt `ApiResult<T>` as new clients are added.

- [ ] **Step 1: Write the failing test (List + Get + Create + Update + Delete success paths and a 409 conflict mapping)**

```csharp
// tests/.../Services/HotstringsApiClientTests.cs
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotstringsApiClientTests
{
    private static HotstringsApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task ListAsync_OnSuccess_ReturnsPagedList()
    {
        var paged = new PagedList<HotstringDto>(
            Items: [new HotstringDto(Guid.NewGuid(), null, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)],
            Page: 1, PageSize: 50, TotalCount: 1, TotalPages: 1, HasNextPage: false, HasPreviousPage: false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        var result = await ClientWith(handler).ListAsync(profileId: null, page: 1, pageSize: 50);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/hotstrings?page=1&pageSize=50");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists for profile", "/api/v1/hotstrings", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        var result = await ClientWith(handler).CreateAsync(new CreateHotstringDto("btw", "by the way"));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task DeleteAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, new ApiProblemDetails(null, "Not Found", 404, null, null, null));

        var result = await ClientWith(handler).DeleteAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;
        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) => new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) { LastRequest = request; return Task.FromResult(_response); }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (compile errors expected — types not yet defined)**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsApiClientTests"`
Expected: BUILD FAIL or test failure ("type or namespace `HotstringsApiClient` not found").

- [ ] **Step 3: Define the API result discriminator and interface**

```csharp
// Services/IHotstringsApiClient.cs
using AHKFlowApp.UI.Blazor.DTOs;
namespace AHKFlowApp.UI.Blazor.Services;

public enum ApiResultStatus { Ok, Validation, NotFound, Conflict, Unauthorized, Forbidden, ServerError, NetworkError }

public sealed record ApiResult<T>(bool IsSuccess, ApiResultStatus Status, T? Value, ApiProblemDetails? Problem)
{
    public static ApiResult<T> Ok(T value) => new(true, ApiResultStatus.Ok, value, null);
    public static ApiResult<T> Failure(ApiResultStatus status, ApiProblemDetails? problem) => new(false, status, default, problem);
}

public sealed record ApiResult(bool IsSuccess, ApiResultStatus Status, ApiProblemDetails? Problem)
{
    public static ApiResult Ok() => new(true, ApiResultStatus.Ok, null);
    public static ApiResult Failure(ApiResultStatus status, ApiProblemDetails? problem) => new(false, status, problem);
}

public interface IHotstringsApiClient
{
    Task<ApiResult<PagedList<HotstringDto>>> ListAsync(Guid? profileId, int page, int pageSize, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
```

- [ ] **Step 4: Implement the client**

```csharp
// Services/HotstringsApiClient.cs
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotstringsApiClient(HttpClient httpClient) : IHotstringsApiClient
{
    private const string BasePath = "api/v1/hotstrings";

    public async Task<ApiResult<PagedList<HotstringDto>>> ListAsync(Guid? profileId, int page, int pageSize, CancellationToken ct = default)
    {
        var query = $"?page={page}&pageSize={pageSize}" + (profileId is { } pid ? $"&profileId={pid}" : "");
        return await SendAsync<PagedList<HotstringDto>>(HttpMethod.Get, BasePath + query, content: null, ct);
    }

    public Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public async Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Delete, $"{BasePath}/{id}");
            using var resp = await httpClient.SendAsync(req, ct);
            if (resp.StatusCode == HttpStatusCode.NoContent) return ApiResult.Ok();
            var problem = await TryReadProblem(resp, ct);
            return ApiResult.Failure(MapStatus(resp.StatusCode), problem);
        }
        catch (HttpRequestException) { return ApiResult.Failure(ApiResultStatus.NetworkError, null); }
    }

    private async Task<ApiResult<T>> SendAsync<T>(HttpMethod method, string path, HttpContent? content, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(method, path) { Content = content };
            using var resp = await httpClient.SendAsync(req, ct);
            if (resp.IsSuccessStatusCode)
            {
                var value = await resp.Content.ReadFromJsonAsync<T>(ct);
                return value is null ? ApiResult<T>.Failure(ApiResultStatus.ServerError, null) : ApiResult<T>.Ok(value);
            }
            var problem = await TryReadProblem(resp, ct);
            return ApiResult<T>.Failure(MapStatus(resp.StatusCode), problem);
        }
        catch (HttpRequestException) { return ApiResult<T>.Failure(ApiResultStatus.NetworkError, null); }
    }

    private static async Task<ApiProblemDetails?> TryReadProblem(HttpResponseMessage resp, CancellationToken ct)
    {
        try { return await resp.Content.ReadFromJsonAsync<ApiProblemDetails>(ct); }
        catch { return null; }
    }

    private static ApiResultStatus MapStatus(HttpStatusCode code) => code switch
    {
        HttpStatusCode.BadRequest or HttpStatusCode.UnprocessableEntity => ApiResultStatus.Validation,
        HttpStatusCode.NotFound => ApiResultStatus.NotFound,
        HttpStatusCode.Conflict => ApiResultStatus.Conflict,
        HttpStatusCode.Unauthorized => ApiResultStatus.Unauthorized,
        HttpStatusCode.Forbidden => ApiResultStatus.Forbidden,
        _ => ApiResultStatus.ServerError,
    };
}
```

- [ ] **Step 5: Register the client in Program.cs**

In `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, add a second `AddHttpClient` registration mirroring the existing one, immediately after the existing `AddHttpClient<IAhkFlowAppApiHttpClient, ...>` block:

```csharp
builder.Services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
})
    .AddHttpMessageHandler<ApiAuthorizationMessageHandler>()
    .AddStandardResilienceHandler();
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsApiClientTests"`
Expected: All 3 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Services/ src/Frontend/AHKFlowApp.UI.Blazor/Program.cs tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs
git commit -m "feat(ui): add typed hotstrings API client"
```

---

## Task 3: API Error Message Factory

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/ApiErrorMessageFactory.cs`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Services/ApiErrorMessageFactoryTests.cs`

- [ ] **Step 1: Write the failing tests**

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class ApiErrorMessageFactoryTests
{
    [Fact]
    public void Build_ForValidationWithErrors_FlattensFieldMessages()
    {
        var problem = new ApiProblemDetails(null, "Validation failed", 400, null, null,
            new Dictionary<string, string[]> { ["Trigger"] = ["must not be empty"], ["Replacement"] = ["must not be empty"] });

        var msg = ApiErrorMessageFactory.Build(ApiResultStatus.Validation, problem);

        msg.Should().Contain("Trigger: must not be empty");
        msg.Should().Contain("Replacement: must not be empty");
    }

    [Fact]
    public void Build_ForConflict_UsesProblemDetailOrFallback()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists for this profile", null, null);
        ApiErrorMessageFactory.Build(ApiResultStatus.Conflict, problem).Should().Be("Trigger already exists for this profile");
    }

    [Fact]
    public void Build_ForNetworkError_ReturnsGenericMessage()
    {
        ApiErrorMessageFactory.Build(ApiResultStatus.NetworkError, null).Should().Contain("Unable to reach the API");
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~ApiErrorMessageFactoryTests"`
Expected: BUILD FAIL.

- [ ] **Step 3: Implement the factory**

```csharp
// Services/ApiErrorMessageFactory.cs
using AHKFlowApp.UI.Blazor.DTOs;
namespace AHKFlowApp.UI.Blazor.Services;

public static class ApiErrorMessageFactory
{
    public static string Build(ApiResultStatus status, ApiProblemDetails? problem) => status switch
    {
        ApiResultStatus.Validation when problem?.Errors is { Count: > 0 } errors =>
            string.Join("; ", errors.SelectMany(kv => kv.Value.Select(v => $"{kv.Key}: {v}"))),
        ApiResultStatus.Validation => problem?.Detail ?? "The request was invalid.",
        ApiResultStatus.NotFound => problem?.Detail ?? "Hotstring not found.",
        ApiResultStatus.Conflict => problem?.Detail ?? "A hotstring with that trigger already exists.",
        ApiResultStatus.Unauthorized => "You are not signed in.",
        ApiResultStatus.Forbidden => "You do not have permission to perform this action.",
        ApiResultStatus.NetworkError => "Unable to reach the API. Check your connection and try again.",
        _ => problem?.Detail ?? "An unexpected error occurred.",
    };
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~ApiErrorMessageFactoryTests"`
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Services/ApiErrorMessageFactory.cs tests/AHKFlowApp.UI.Blazor.Tests/Services/ApiErrorMessageFactoryTests.cs
git commit -m "feat(ui): add API error message factory for hotstrings"
```

---

## Task 4: Edit Model with Validation

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs`

DataAnnotations are used here (not FluentValidation) because MudForm integrates natively with DataAnnotationsValidator. Rules mirror the backend FluentValidation rules.

- [ ] **Step 1: Create the edit model**

```csharp
// Validation/HotstringEditModel.cs
using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;
namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotstringEditModel
{
    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Trigger is required.")]
    [MaxLength(50, ErrorMessage = "Trigger must be 50 characters or fewer.")]
    public string Trigger { get; set; } = "";

    [Required(ErrorMessage = "Replacement is required.")]
    [MaxLength(4000, ErrorMessage = "Replacement must be 4000 characters or fewer.")]
    public string Replacement { get; set; } = "";

    public Guid? ProfileId { get; set; }
    public bool IsEndingCharacterRequired { get; set; } = true;
    public bool IsTriggerInsideWord { get; set; } = true;

    public static HotstringEditModel FromDto(HotstringDto dto) => new()
    {
        Id = dto.Id, Trigger = dto.Trigger, Replacement = dto.Replacement,
        ProfileId = dto.ProfileId,
        IsEndingCharacterRequired = dto.IsEndingCharacterRequired,
        IsTriggerInsideWord = dto.IsTriggerInsideWord,
    };

    public CreateHotstringDto ToCreateDto() => new(Trigger, Replacement, ProfileId, IsEndingCharacterRequired, IsTriggerInsideWord);
    public UpdateHotstringDto ToUpdateDto() => new(Trigger, Replacement, ProfileId, IsEndingCharacterRequired, IsTriggerInsideWord);
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs
git commit -m "feat(ui): add hotstring edit model with validation"
```

---

## Task 5: Hotstrings Page — List View Skeleton

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`

- [ ] **Step 1: Write the failing test for the loading + empty + error states**

```csharp
// tests/.../Pages/HotstringsPageTests.cs
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HotstringsPageTests : BunitContext
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();

    public HotstringsPageTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private static PagedList<HotstringDto> Page(params HotstringDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        var dto = new HotstringDto(Guid.NewGuid(), null, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)));

        var cut = Render<Hotstrings>();
        cut.WaitForState(() => cut.Markup.Contains("btw"));

        cut.Markup.Should().Contain("by the way");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Failure(ApiResultStatus.NetworkError, null));

        var cut = Render<Hotstrings>();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure (page doesn't exist)**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsPageTests"`
Expected: BUILD FAIL.

- [ ] **Step 3: Implement the page (read-only list, no editing yet — that comes in Task 6)**

```razor
@* Pages/Hotstrings.razor *@
@page "/hotstrings"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@implements IDisposable

<PageTitle>Hotstrings</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Hotstrings</MudText>

<MudPaper Class="pa-4">
    @if (_loading)
    {
        <MudProgressCircular Color="Color.Primary" Indeterminate="true" Size="Size.Small" />
        <MudText Typo="Typo.body2" Class="mt-2">Loading hotstrings...</MudText>
    }
    else if (_loadError is not null)
    {
        <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
        <MudButton Variant="Variant.Outlined" Color="Color.Primary" OnClick="LoadAsync">Retry</MudButton>
    }
    else
    {
        <MudTable Items="_items" Dense="true" Hover="true">
            <HeaderContent>
                <MudTh>Trigger</MudTh>
                <MudTh>Replacement</MudTh>
                <MudTh>Ending char required</MudTh>
                <MudTh>Inside word</MudTh>
                <MudTh>Actions</MudTh>
            </HeaderContent>
            <RowTemplate>
                <MudTd>@context.Trigger</MudTd>
                <MudTd>@context.Replacement</MudTd>
                <MudTd>@context.IsEndingCharacterRequired</MudTd>
                <MudTd>@context.IsTriggerInsideWord</MudTd>
                <MudTd></MudTd>
            </RowTemplate>
            <NoRecordsContent>
                <MudText>No hotstrings yet.</MudText>
            </NoRecordsContent>
        </MudTable>
    }
</MudPaper>

@code {
    [Inject] private IHotstringsApiClient Api { get; set; } = default!;

    private List<HotstringDto> _items = [];
    private bool _loading = true;
    private string? _loadError;
    private readonly CancellationTokenSource _cts = new();

    protected override Task OnInitializedAsync() => LoadAsync();

    private async Task LoadAsync()
    {
        _loading = true; _loadError = null; StateHasChanged();
        var result = await Api.ListAsync(profileId: null, page: 1, pageSize: 200, _cts.Token);
        if (result.IsSuccess) _items = [.. result.Value!.Items];
        else _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        _loading = false;
    }

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

- [ ] **Step 4: Add nav link**

Modify `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor` to add a link after the Health entry:

```razor
<MudNavLink Href="hotstrings"
            Icon="@Icons.Material.Filled.Keyboard">
    Hotstrings
</MudNavLink>
```

- [ ] **Step 5: Run tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsPageTests"`
Expected: Both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs
git commit -m "feat(ui): add hotstrings list page"
```

---

## Task 6: Inline Row Editing — Add and Edit

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`

The MudTable strategy:
- Each row has its own `HotstringEditModel` shadow stored in a dictionary keyed by hotstring `Id` (or `Guid.Empty` for the draft "new" row). `Guid.Empty` is safe as a sentinel because real hotstring Ids come from `Guid.NewGuid()` server-side and will never collide.
- The "Add" button creates a draft `HotstringEditModel` in `_editing[Guid.Empty]` and `VisibleRows()` prepends a placeholder DTO with `Id = Guid.Empty`.
- The pencil button copies the row's DTO into `_editing[id]`.
- Save commits via Create/Update; Cancel removes from `_editing`.

**Test selector strategy:** MudBlazor 9.x `MudComponentBase` captures unknown attributes into `UserAttributes` and most components splat them onto their root element. To stay robust against version drift we use **stable `Class` names** for row-level markers (`Class` is always forwarded) and **`UserAttributes`** for input-level markers (the only documented mechanism for MudTextField). Tests target `tr.draft-row` / `tr.edit-row` and `input[data-test="trigger-input"]`. Unique action-button classes (`add-hotstring`, `commit-edit`, `cancel-edit`, `start-edit`, `delete`) remain the primary click targets.

- [ ] **Step 1: Write the failing test for the add flow**

Add to `HotstringsPageTests.cs`:

```csharp
[Fact]
public void Page_AddButton_InsertsDraftRow()
{
    _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page()));

    var cut = Render<Hotstrings>();
    cut.WaitForState(() => cut.Markup.Contains("No hotstrings yet") || cut.Find("table") is not null);

    cut.Find("button.add-hotstring").Click();

    cut.WaitForAssertion(() => cut.Find("td.draft-row").Should().NotBeNull());
}

[Fact]
public async Task Page_SaveDraftRow_CallsCreateAndRefreshes()
{
    _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page()));
    _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<HotstringDto>.Ok(new HotstringDto(Guid.NewGuid(), null, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

    var cut = Render<Hotstrings>();
    cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
    cut.Find("button.add-hotstring").Click();

    cut.Find("input[data-test=\"trigger-input\"]").Change("btw");
    cut.Find("input[data-test=\"replacement-input\"]").Change("by the way");
    cut.Find("button.commit-edit").Click();

    cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
        Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
        Arg.Any<CancellationToken>()));
    await Task.CompletedTask;
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL (no add button, no draft row).

- [ ] **Step 3: Replace the page implementation with the editable version**

Replace the file body of `Pages/Hotstrings.razor` with:

```razor
@page "/hotstrings"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor
@implements IDisposable

<PageTitle>Hotstrings</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Hotstrings</MudText>

<MudPaper Class="pa-4">
    <MudButton Class="add-hotstring mb-3" Variant="Variant.Filled" Color="Color.Primary"
               StartIcon="@Icons.Material.Filled.Add" OnClick="StartAdd"
               Disabled="@(_editing.ContainsKey(Guid.Empty))">
        Add hotstring
    </MudButton>

    @if (_loading)
    {
        <MudProgressCircular Indeterminate="true" Size="Size.Small" />
    }
    else if (_loadError is not null)
    {
        <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
        <MudButton Variant="Variant.Outlined" OnClick="LoadAsync">Retry</MudButton>
    }
    else
    {
        <MudTable Items="VisibleRows()" Dense="true" Hover="true">
            <HeaderContent>
                <MudTh>Trigger</MudTh>
                <MudTh>Replacement</MudTh>
                <MudTh>Ending char</MudTh>
                <MudTh>Inside word</MudTh>
                <MudTh Style="width:160px">Actions</MudTh>
            </HeaderContent>
            <RowTemplate>
                @if (_editing.TryGetValue(context.Id, out var edit))
                {
                    <MudTd Class="@(context.Id == Guid.Empty ? "draft-row" : "edit-row")">
                        <MudTextField @bind-Value="edit.Trigger" Required="true" MaxLength="50" Immediate="true"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "trigger-input" })" />
                    </MudTd>
                    <MudTd>
                        <MudTextField @bind-Value="edit.Replacement" Required="true" MaxLength="4000" Immediate="true"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "replacement-input" })" />
                    </MudTd>
                    <MudTd><MudCheckBox @bind-Value="edit.IsEndingCharacterRequired" /></MudTd>
                    <MudTd><MudCheckBox @bind-Value="edit.IsTriggerInsideWord" /></MudTd>
                    <MudTd>
                        <MudIconButton Class="commit-edit" Icon="@Icons.Material.Filled.Check"
                                       Color="Color.Success" OnClick="() => CommitEditAsync(context.Id)" />
                        <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.Close"
                                       Color="Color.Default" OnClick="() => CancelEdit(context.Id)" />
                    </MudTd>
                }
                else
                {
                    <MudTd>@context.Trigger</MudTd>
                    <MudTd>@context.Replacement</MudTd>
                    <MudTd>@context.IsEndingCharacterRequired</MudTd>
                    <MudTd>@context.IsTriggerInsideWord</MudTd>
                    <MudTd>
                        <MudIconButton Class="start-edit" Icon="@Icons.Material.Filled.Edit"
                                       OnClick="() => StartEdit(context)" />
                        <MudIconButton Class="delete" Icon="@Icons.Material.Filled.Delete" Color="Color.Error"
                                       OnClick="() => DeleteAsync(context)" />
                    </MudTd>
                }
            </RowTemplate>
            <NoRecordsContent><MudText>No hotstrings yet.</MudText></NoRecordsContent>
        </MudTable>
    }
</MudPaper>

@code {
    [Inject] private IHotstringsApiClient Api { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;

    private List<HotstringDto> _items = [];
    private readonly Dictionary<Guid, HotstringEditModel> _editing = new();
    private bool _loading = true;
    private string? _loadError;
    private readonly CancellationTokenSource _cts = new();

    private static readonly HotstringDto _draftPlaceholder = new(
        Guid.Empty, null, "", "", true, true, DateTimeOffset.MinValue, DateTimeOffset.MinValue);

    protected override Task OnInitializedAsync() => LoadAsync();

    private IEnumerable<HotstringDto> VisibleRows()
    {
        if (_editing.ContainsKey(Guid.Empty)) yield return _draftPlaceholder;
        foreach (var item in _items) yield return item;
    }

    private async Task LoadAsync()
    {
        _loading = true; _loadError = null; StateHasChanged();
        var result = await Api.ListAsync(profileId: null, page: 1, pageSize: 200, _cts.Token);
        if (result.IsSuccess) _items = [.. result.Value!.Items];
        else _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        _loading = false;
    }

    private void StartAdd() => _editing[Guid.Empty] = new HotstringEditModel();

    private void StartEdit(HotstringDto dto) => _editing[dto.Id] = HotstringEditModel.FromDto(dto);

    private void CancelEdit(Guid id) => _editing.Remove(id);

    private async Task CommitEditAsync(Guid id)
    {
        if (!_editing.TryGetValue(id, out var edit)) return;

        if (string.IsNullOrWhiteSpace(edit.Trigger) || string.IsNullOrWhiteSpace(edit.Replacement))
        {
            Snackbar.Add("Trigger and Replacement are required.", Severity.Warning);
            return;
        }

        if (id == Guid.Empty)
        {
            var result = await Api.CreateAsync(edit.ToCreateDto(), _cts.Token);
            if (result.IsSuccess) { _editing.Remove(id); Snackbar.Add("Hotstring created.", Severity.Success); await LoadAsync(); }
            else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
        else
        {
            var result = await Api.UpdateAsync(id, edit.ToUpdateDto(), _cts.Token);
            if (result.IsSuccess) { _editing.Remove(id); Snackbar.Add("Hotstring updated.", Severity.Success); await LoadAsync(); }
            else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }

    private async Task DeleteAsync(HotstringDto dto)
    {
        var confirm = await DialogService.ShowMessageBox(
            title: "Delete hotstring?",
            markupMessage: new MarkupString($"Delete <strong>{dto.Trigger}</strong>? This cannot be undone."),
            yesText: "Delete", cancelText: "Cancel");
        if (confirm != true) return;

        var result = await Api.DeleteAsync(dto.Id, _cts.Token);
        if (result.IsSuccess) { Snackbar.Add("Hotstring deleted.", Severity.Success); await LoadAsync(); }
        else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

- [ ] **Step 4: Run tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsPageTests"`
Expected: All tests (read-only + add) PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs
git commit -m "feat(ui): inline add+edit on hotstrings table"
```

---

## Task 7: Edit and Delete Tests

**Files:**
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`

- [ ] **Step 1: Add edit and delete tests**

```csharp
[Fact]
public async Task Page_EditExistingRow_CallsUpdate()
{
    var dto = new HotstringDto(Guid.NewGuid(), null, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
    _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)));
    _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<HotstringDto>.Ok(dto with { Replacement = "by the way!" }));

    var cut = Render<Hotstrings>();
    cut.WaitForAssertion(() => cut.Find("button.start-edit"));
    cut.Find("button.start-edit").Click();
    cut.Find("input[data-test=\"replacement-input\"]").Change("by the way!");
    cut.Find("button.commit-edit").Click();

    cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
        Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"), Arg.Any<CancellationToken>()));
    await Task.CompletedTask;
}

[Fact]
public async Task Page_DeleteRow_CallsDeleteAfterConfirm()
{
    var dto = new HotstringDto(Guid.NewGuid(), null, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
    _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)));
    _api.DeleteAsync(dto.Id, Arg.Any<CancellationToken>()).Returns(ApiResult.Ok());

    JSInterop.SetupVoid("Mud.Dialog.show").SetVoidResult();

    var cut = Render<Hotstrings>();
    cut.WaitForAssertion(() => cut.Find("button.delete"));
    cut.Find("button.delete").Click();

    cut.WaitForAssertion(() => cut.FindAll(".mud-message-box").Count > 0);
    cut.FindAll(".mud-button").First(b => b.TextContent.Contains("Delete")).Click();

    cut.WaitForAssertion(() => _api.Received(1).DeleteAsync(dto.Id, Arg.Any<CancellationToken>()));
    await Task.CompletedTask;
}

[Fact]
public async Task Page_OnConflictResponse_ShowsErrorSnackbar()
{
    _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page()));
    _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Conflict,
            new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", null, null)));

    var cut = Render<Hotstrings>();
    cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
    cut.Find("button.add-hotstring").Click();
    cut.Find("input[data-test=\"trigger-input\"]").Change("btw");
    cut.Find("input[data-test=\"replacement-input\"]").Change("by the way");
    cut.Find("button.commit-edit").Click();

    cut.WaitForAssertion(() => cut.Markup.Contains("Trigger already exists") || cut.FindAll(".mud-snackbar").Count > 0);
    await Task.CompletedTask;
}
```

- [ ] **Step 2: Run tests**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsPageTests"`
Expected: All HotstringsPageTests PASS. If the MudMessageBox JS interop test fails because of bUnit's headless renderer, replace it with a behaviour test that asserts `_api.Received(1).DeleteAsync(...)` and verifies the dialog appears in markup, accepting that bUnit cannot click through `MudMessageBox` reliably — in that case mark the click step `[Fact(Skip = "MudMessageBox interop limitation, covered by E2E in Task 9")]`.

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs
git commit -m "test(ui): cover hotstring edit, delete, conflict flows"
```

---

## Task 8: Update Frontend CLAUDE.md

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`

- [ ] **Step 1: Soften the dialog convention to allow inline editing for tabular data**

Replace the line `- IDialogService.ShowAsync<T> for create/edit forms` with:

```
- `IDialogService.ShowAsync<T>` for create/edit forms with non-trivial layouts (multi-section, tabs, file upload, etc.)
- Inline `MudTable` row editing is acceptable for simple tabular CRUD (≤6 short fields). Examples: hotstrings page.
- `IDialogService.ShowMessageBox(...)` for delete confirmations
```

- [ ] **Step 2: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md
git commit -m "docs(ui): allow inline MudTable editing for simple CRUD"
```

---

## Task 9: SPA Auth Bypass + E2E Project Scaffold

**Files (Frontend, test-only auth):**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Auth/TestAuthenticationProvider.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.E2E.json`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` (branch on `Auth:UseTestProvider`)

**Files (E2E project):**
- Create: `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`
- Create: `tests/AHKFlowApp.E2E.Tests/GlobalUsings.cs`
- Create: `tests/AHKFlowApp.E2E.Tests/Fixtures/TestAuthHandler.cs`
- Create: `tests/AHKFlowApp.E2E.Tests/Fixtures/ApiFactory.cs`
- Create: `tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs`
- Create: `tests/AHKFlowApp.E2E.Tests/Fixtures/StackFixture.cs`
- Modify: `AHKFlowApp.sln` (add E2E project)
- Modify: `Directory.Packages.props` (Playwright, Mvc.Testing, Yarp.ReverseProxy)

**Architecture (why three pieces):**
1. **Backend auth bypass** — `TestAuthHandler` swapped in via `WebApplicationFactory.ConfigureTestServices` so `[Authorize]` controllers accept synthetic principals.
2. **Frontend auth bypass** — MSAL.js cannot run headless without a real Entra tenant. We add a `TestAuthenticationProvider : AuthenticationStateProvider` compiled into the regular Blazor build but only registered when `Auth:UseTestProvider == true` in `appsettings.E2E.json`. The MSAL pipeline is conditionally skipped.
3. **Hosting** — `SpaHost` is a Kestrel `WebApplication` that serves the published Blazor `wwwroot` (with the E2E `appsettings.json` overlay) on `http://127.0.0.1:0` and reverse-proxies `/api/*` to `ApiFactory.Server.CreateClient()` via YARP. Playwright navigates to the SpaHost URL.

- [ ] **Step 1: Add the test authentication provider to Blazor**

```csharp
// src/Frontend/AHKFlowApp.UI.Blazor/Auth/TestAuthenticationProvider.cs
using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;

namespace AHKFlowApp.UI.Blazor.Auth;

public sealed class TestAuthenticationProvider : AuthenticationStateProvider
{
    public const string TestOwnerOid = "11111111-1111-1111-1111-111111111111";

    public override Task<AuthenticationState> GetAuthenticationStateAsync()
    {
        var identity = new ClaimsIdentity(
        [
            new Claim("oid", TestOwnerOid),
            new Claim("name", "Test User"),
            new Claim("preferred_username", "test@example.com"),
            new Claim("http://schemas.microsoft.com/identity/claims/scope", "access_as_user"),
        ], authenticationType: "Test");
        return Task.FromResult(new AuthenticationState(new ClaimsPrincipal(identity)));
    }
}
```

- [ ] **Step 2: Add the E2E appsettings overlay**

```json
// src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.E2E.json
{
  "Auth": { "UseTestProvider": true },
  "ApiBaseUrl": "/"
}
```

> Add `appsettings.E2E.json` to the project as `<Content CopyToPublishDirectory="PreserveNewest" />` if not picked up by default `wwwroot/**/*` globs.

- [ ] **Step 3: Branch Program.cs on the flag**

In `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, replace the unconditional MSAL + AuthorizationCore registration with a branch:

```csharp
var useTestAuth = builder.Configuration.GetValue<bool>("Auth:UseTestProvider");

if (useTestAuth)
{
    builder.Services.AddAuthorizationCore();
    builder.Services.AddScoped<AuthenticationStateProvider, TestAuthenticationProvider>();
    builder.Services.AddScoped<ApiAuthorizationMessageHandler>(_ => new NoopAuthorizationMessageHandler());
}
else
{
    // existing MSAL pipeline (AddMsalAuthentication, AddAuthorizationCore, ApiAuthorizationMessageHandler with bearer token)
}
```

`NoopAuthorizationMessageHandler` is a `DelegatingHandler` subclass of `ApiAuthorizationMessageHandler` (or replace it) that simply forwards the request without attaching a bearer token. Backend auth is handled by `TestAuthHandler` regardless of headers.

- [ ] **Step 4: Build the Blazor project**

Run: `dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release`
Expected: Build succeeded. The Test provider does not affect the production build path because the flag defaults to false in `appsettings.json`.

- [ ] **Step 5: Create the E2E project**

```xml
<!-- tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="Microsoft.Identity.Web" />
    <PackageReference Include="Microsoft.Playwright" />
    <PackageReference Include="Yarp.ReverseProxy" />
    <PackageReference Include="Testcontainers.MsSql" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.API\AHKFlowApp.API.csproj" />
    <ProjectReference Include="..\..\src\Frontend\AHKFlowApp.UI.Blazor\AHKFlowApp.UI.Blazor.csproj" />
    <ProjectReference Include="..\..\src\Backend\AHKFlowApp.Infrastructure\AHKFlowApp.Infrastructure.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 6: Add packages and register project**

Run (resolves latest stable, updates `Directory.Packages.props`):
```bash
dotnet add tests/AHKFlowApp.E2E.Tests package Microsoft.AspNetCore.Mvc.Testing
dotnet add tests/AHKFlowApp.E2E.Tests package Microsoft.Identity.Web
dotnet add tests/AHKFlowApp.E2E.Tests package Microsoft.Playwright
dotnet add tests/AHKFlowApp.E2E.Tests package Yarp.ReverseProxy
dotnet add tests/AHKFlowApp.E2E.Tests package Testcontainers.MsSql
dotnet sln add tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj
```

- [ ] **Step 7: Implement the backend test auth handler**

```csharp
// tests/AHKFlowApp.E2E.Tests/Fixtures/TestAuthHandler.cs
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Test";
    public static readonly Guid TestOwnerOid = Guid.Parse("11111111-1111-1111-1111-111111111111");

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var claims = new[]
        {
            new Claim("oid", TestOwnerOid.ToString()),
            new Claim("name", "Test User"),
            new Claim("preferred_username", "test@example.com"),
            new Claim("http://schemas.microsoft.com/identity/claims/scope", "access_as_user"),
        };
        var identity = new ClaimsIdentity(claims, SchemeName);
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }
}
```

- [ ] **Step 8: Implement ApiFactory (WebApplicationFactory + Testcontainers SQL)**

```csharp
// tests/AHKFlowApp.E2E.Tests/Fixtures/ApiFactory.cs
using AHKFlowApp.Infrastructure;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Testcontainers.MsSql;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public MsSqlContainer Sql { get; } = new MsSqlBuilder().Build();

    public async Task StartAsync()
    {
        await Sql.StartAsync();
        using var scope = Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Test");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = Sql.GetConnectionString(),
            });
        });
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            services.PostConfigure<AuthorizationOptions>(opts =>
            {
                opts.DefaultPolicy = new AuthorizationPolicyBuilder(TestAuthHandler.SchemeName)
                    .RequireAuthenticatedUser().Build();
            });
        });
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await Sql.DisposeAsync();
    }
}
```

> If `Program` is internal, add `public partial class Program { }` to `src/Backend/AHKFlowApp.API/Program.cs` (Microsoft's documented WebApplicationFactory pattern).

- [ ] **Step 9: Implement SpaHost (Kestrel + YARP reverse proxy + static Blazor)**

```csharp
// tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Yarp.ReverseProxy.Forwarder;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class SpaHost : IAsyncDisposable
{
    private readonly WebApplication _app;
    public string BaseUrl { get; }

    private SpaHost(WebApplication app, string baseUrl) { _app = app; BaseUrl = baseUrl; }

    public static async Task<SpaHost> StartAsync(string publishedWwwroot, HttpMessageInvoker apiInvoker, string apiBaseUrl)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddHttpForwarder();

        var app = builder.Build();
        var forwarder = app.Services.GetRequiredService<IHttpForwarder>();

        app.Map("/api/{**catch-all}", async ctx =>
        {
            await forwarder.SendAsync(ctx, apiBaseUrl, apiInvoker, ForwarderRequestConfig.Empty);
        });

        var fp = new PhysicalFileProvider(publishedWwwroot);
        app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = fp });
        app.UseStaticFiles(new StaticFileOptions { FileProvider = fp });
        // SPA fallback — serve index.html for unknown routes
        app.MapFallback(async ctx =>
        {
            ctx.Response.ContentType = "text/html";
            await ctx.Response.SendFileAsync(Path.Combine(publishedWwwroot, "index.html"));
        });

        await app.StartAsync();
        var addr = app.Urls.First();
        return new SpaHost(app, addr);
    }

    public async ValueTask DisposeAsync() => await _app.DisposeAsync();
}
```

- [ ] **Step 10: Implement StackFixture (orchestrator)**

```csharp
// tests/AHKFlowApp.E2E.Tests/Fixtures/StackFixture.cs
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class StackFixture : IAsyncLifetime
{
    public ApiFactory Api { get; } = new();
    public SpaHost Spa { get; private set; } = default!;
    public IPlaywright Playwright { get; private set; } = default!;
    public IBrowser Browser { get; private set; } = default!;

    public async Task InitializeAsync()
    {
        await Api.StartAsync();

        // Locate published Blazor wwwroot. Engineer must publish first via test setup script (Step 11).
        var wwwroot = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", "..",
            "src", "Frontend", "AHKFlowApp.UI.Blazor", "bin", "Release", "net10.0", "publish", "wwwroot"));

        if (!Directory.Exists(wwwroot))
            throw new DirectoryNotFoundException($"Publish wwwroot not found at {wwwroot}. Run: dotnet publish src/Frontend/AHKFlowApp.UI.Blazor -c Release");

        Spa = await SpaHost.StartAsync(wwwroot, Api.CreateClient(), Api.Server.BaseAddress.ToString());

        Microsoft.Playwright.Program.Main(["install", "chromium"]);
        Playwright = await Microsoft.Playwright.Playwright.CreateAsync();
        Browser = await Playwright.Chromium.LaunchAsync(new() { Headless = true });
    }

    public async Task DisposeAsync()
    {
        await Browser.CloseAsync();
        Playwright.Dispose();
        await Spa.DisposeAsync();
        await Api.DisposeAsync();
    }
}
```

- [ ] **Step 11: Add the publish step to the test project**

Add to `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`:

```xml
<Target Name="PublishBlazorForE2E" BeforeTargets="Build">
  <Exec Command="dotnet publish ..\..\src\Frontend\AHKFlowApp.UI.Blazor -c $(Configuration) --no-self-contained -o ..\..\src\Frontend\AHKFlowApp.UI.Blazor\bin\$(Configuration)\net10.0\publish" />
</Target>
```

- [ ] **Step 12: Build to confirm scaffold compiles and Blazor publishes**

Run: `dotnet build tests/AHKFlowApp.E2E.Tests --configuration Release`
Expected: Build succeeded; Blazor publish output exists at the expected path.

- [ ] **Step 13: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Auth/ src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.E2E.json src/Frontend/AHKFlowApp.UI.Blazor/Program.cs tests/AHKFlowApp.E2E.Tests/ AHKFlowApp.sln Directory.Packages.props
git commit -m "test(e2e): scaffold playwright SPA-driven E2E with auth bypass"
```

---

## Task 10: E2E Hotstrings CRUD Flow (Browser-Driven)

**Files:**
- Create: `tests/AHKFlowApp.E2E.Tests/HotstringsCrudFlowTests.cs`

This test launches the real Blazor SPA in a headless Chromium browser, navigates to `/hotstrings`, and exercises Add → Edit → Delete via the UI. Backend persists to a Testcontainers SQL Server. The duplicate-trigger check verifies the conflict snackbar surfaces.

- [ ] **Step 1: Implement the Playwright UI flow test**

```csharp
// tests/AHKFlowApp.E2E.Tests/HotstringsCrudFlowTests.cs
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

public sealed class HotstringsCrudFlowTests(StackFixture fixture) : IClassFixture<StackFixture>
{
    [Fact]
    public async Task CreateEditDelete_DrivesBlazorSpaThroughBrowser()
    {
        await using var ctx = await fixture.Browser.NewContextAsync();
        var page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        // Create
        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("td.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "btw");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "by the way");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");
        (await page.Locator("table tbody tr").CountAsync()).Should().BeGreaterThan(0);
        (await page.GetByText("by the way").IsVisibleAsync()).Should().BeTrue();

        // Edit
        await page.ClickAsync("button.start-edit");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "by the way!");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring updated.");
        (await page.GetByText("by the way!").IsVisibleAsync()).Should().BeTrue();

        // Delete (MudMessageBox confirm)
        await page.ClickAsync("button.delete");
        await page.GetByRole(AriaRole.Button, new() { Name = "Delete" }).Last.ClickAsync();
        await page.WaitForSelectorAsync("text=Hotstring deleted.");
        await page.WaitForSelectorAsync("text=No hotstrings yet.");
    }

    [Fact]
    public async Task DuplicateTrigger_ShowsConflictSnackbar()
    {
        await using var ctx = await fixture.Browser.NewContextAsync();
        var page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        // First insert succeeds
        await page.ClickAsync("button.add-hotstring");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "dup");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "duplicate");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        // Second insert with same trigger → conflict
        await page.ClickAsync("button.add-hotstring");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "dup");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "duplicate again");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=/already exists/i");
    }
}
```

- [ ] **Step 2: Run the test**

Run: `dotnet test tests/AHKFlowApp.E2E.Tests --configuration Release --verbosity normal`
Expected: Both tests PASS. Requires Docker Desktop running (Testcontainers SQL Server) and a working Chromium install (Playwright auto-installs on first run via Step 11 of Task 9).

> **Troubleshooting:** If Playwright fails to launch, manually run `pwsh tests/AHKFlowApp.E2E.Tests/bin/Release/net10.0/playwright.ps1 install chromium`. If the Blazor SPA fails to load, check that `appsettings.E2E.json` was published and that `Auth:UseTestProvider` resolves to `true` at runtime (browser DevTools → Network → `appsettings.E2E.json` should return 200).

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.E2E.Tests/HotstringsCrudFlowTests.cs
git commit -m "test(e2e): playwright-driven hotstrings create/edit/delete + conflict"
```

---

## Task 11: Manual Verification

**Files:** none — this is a runtime check against a real browser.

- [ ] **Step 1: Start the API with Docker SQL**

Run: `dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "https + Docker SQL (Recommended)"`
Expected: API listening on `http://localhost:5600`, `/health` returns Healthy.

- [ ] **Step 2: Start the Blazor frontend in a second terminal**

Run: `dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor`
Expected: Frontend listening on `http://localhost:5601`.

- [ ] **Step 3: Sign in, then walk the flow in the browser**

- Click "Hotstrings" in the nav → page loads, shows "No hotstrings yet."
- Click "Add hotstring" → draft row appears with empty Trigger / Replacement.
- Type `btw` and `by the way` → click ✓ → row commits, snackbar "Hotstring created.", list refreshes with the new row.
- Click ✏ on the new row → row enters edit mode → change Replacement to `by the way!` → click ✓ → snackbar "Hotstring updated.", row shows new value.
- Try to add a second `btw` → snackbar shows the conflict message from the API.
- Click 🗑 → confirmation dialog → click "Delete" → snackbar "Hotstring deleted.", row gone.

- [ ] **Step 4: Refresh the browser** — the surviving rows should reload from the API (proves persistence).

---

## Task 12: Final Verification

- [ ] **Step 1: Format**

Run: `dotnet format`
Expected: No changes (or only whitespace fixes — commit them).

- [ ] **Step 2: Build full solution**

Run: `dotnet build --configuration Release`
Expected: Build succeeded, 0 errors, 0 warnings introduced.

- [ ] **Step 3: Run all tests**

Run: `dotnet test --configuration Release --verbosity normal`
Expected: All tests pass, including new bUnit tests and E2E tests.

- [ ] **Step 4: Push and open PR**

```bash
git push -u origin feature/014-hotstrings-ui-crud
gh pr create --title "feat: Hotstrings UI CRUD (014)" --body "$(cat <<'EOF'
## Summary
- Adds inline-editable Hotstrings page (`/hotstrings`) using MudTable
- New typed `IHotstringsApiClient` (introduces project `ApiResult<T>` convention) for `/api/v1/hotstrings`
- bUnit coverage for list, create, edit, delete, conflict
- Playwright E2E project — drives the real Blazor SPA in headless Chromium against a Testcontainers SQL backend, with MSAL bypassed via a flag-gated `TestAuthenticationProvider`
- Soften Frontend CLAUDE.md to allow inline MudTable editing for simple tabular CRUD

## Test plan
- [x] dotnet build / dotnet test green
- [x] Manual: create / edit / delete / duplicate-trigger conflict in browser
- [ ] CI green
EOF
)"
```

---

## Verification Section

**Build:** `dotnet build --configuration Release` — 0 errors.
**Unit tests:** `dotnet test tests/AHKFlowApp.UI.Blazor.Tests` — all green; HotstringsApiClient (3), ApiErrorMessageFactory (3), HotstringsPage (≥6) tests.
**E2E:** `dotnet test tests/AHKFlowApp.E2E.Tests` — Playwright drives the real Blazor SPA through create/edit/delete + duplicate-trigger conflict against Testcontainers SQL.
**Manual UI:** Run API (`5600`) + Blazor (`5601`), sign in, add/edit/delete a hotstring, observe snackbar feedback, refresh to confirm persistence.
**Format:** `dotnet format` clean.

---

## Critical Files Reference

**Backend reuse (existing — read, don't modify):**
- `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs` — endpoint contract
- `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs` — wire shape
- `src/Backend/AHKFlowApp.API/Middleware/GlobalExceptionMiddleware.cs` — error envelope shape

**Frontend patterns (existing — mirror these):**
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/AhkFlowAppApiHttpClient.cs` — typed-client convention
- `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs:40-46` — `AddHttpClient` + auth handler + resilience pipeline
- `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Health.razor` — page structure, loading/error pattern
- `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HealthPageTests.cs` — bUnit setup pattern

---

## Open Questions

- CI Playwright browser install — bake into Docker image or run `playwright.ps1 install chromium` per job? Latter cheaper, slower.
- MudMessageBox click under bUnit — if brittle, skip that one click test (E2E covers it).
- Testcontainers on CI runner — existing API integration tests use it, so should work; confirm new E2E job too.
- `appsettings.E2E.json` published correctly — verify `<Content>` glob picks it up; add explicit MSBuild item if not.
- `NoopAuthorizationMessageHandler` — replace base class, or subclass it? Depends on existing `ApiAuthorizationMessageHandler` shape; check at impl time.
