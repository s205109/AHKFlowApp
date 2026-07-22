# Hotkey Redesign — Wave 1 UI (Typed Actions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Hotkeys page and dialog onto the seven-kind `HotkeyActionKind` model — a registry-backed key picker, per-kind action panels, a live preview panel, a collapsed grid with a single-sourced action display, and the inline-edit gating that surfaces un-migratable legacy rows.

**Architecture:** The frontend mirrors backend contracts by hand (the Blazor project has **zero `ProjectReference`s**), so this plan re-mirrors the hotkey DTOs and adds one new backend endpoint — `GET /api/v1/hotkeys/keys` — that serves the canonical key registry to the picker. The registry stays the single source of truth for key facts; nothing about the five role grammars is reimplemented client-side. Field-level validation errors arrive from the server, mapped onto fields from both the debounced preview call and the save response, exactly as `HotstringEditDialog` already does.

**Tech Stack:** .NET 10, Blazor WebAssembly, MudBlazor 9.3.0, xUnit + FluentAssertions + NSubstitute, bUnit, Playwright (E2E).

**Source spec:** `docs/superpowers/specs/2026-07-21-hotkey-redesign-design.md` (§3, §4, §5, §6, §9 W1, §10 UI, §11).
**Companion plan:** `docs/superpowers/plans/2026-07-22-hotkey-redesign-w1-backend-plan.md` — the backend half of the same wave.

---

## Landing Precondition (read before Task 1)

The backend plan's Task 6 removes `Action`/`Parameters` from `HotkeyDto`/`CreateHotkeyDto`/`UpdateHotkeyDto`. The frontend keeps its own DTO mirror, so **nothing fails to compile** — the Hotkeys page breaks at *runtime*: every create/update posts a payload with no `ActionKind` fields (400 from the kind-conditional validator) and every read renders an empty action.

`deploy-api.yml` fires on push to `main` under `src/Backend/**`; `deploy-frontend.yml` fires under `src/Frontend/**`. So merging the backend PR alone **auto-deploys the API to TEST against the old UI**. Two sequential PRs cannot avoid this; the chosen mitigation is to make the window as small as possible:

> **Hard precondition:** this plan's PR must be **reviewed, approved, and green** *before* the backend PR merges. Then merge backend, then merge this immediately. The broken window is merge-to-merge (API deploy + SWA build, realistically 5–15 min), **never** review time. If this PR is blocked in review, the backend PR waits.

Task 1 is the only task that can be executed before the backend plan lands — it depends solely on Wave 0's `HotkeyKeys`, which is already merged. **Tasks 2–10 require backend Task 6 complete** (typed DTOs on the API).

---

## Global Constraints

- Target framework `net10.0`; Microsoft.* packages on 10.x. Never hardcode package versions; CPM (`Directory.Packages.props`) — no `Version=` in csproj.
- Primary constructors for DI; records for DTOs; file-scoped namespaces; Allman braces; `sealed` by default; `internal` unless a wider surface is needed.
- MudBlazor components only — no raw HTML inputs or buttons. **Verify every MudBlazor parameter against the MudMCP server** (`mcp__mudblazor__get_component_parameters`, `get_enum_values`) before writing markup; it serves the pinned 9.3.0 docs.
- `[Inject]` properties with `= default!`. `ISnackbar.Add()` for feedback. No `StateHasChanged()` after standard event handlers (it *is* required inside fire-and-forget preview continuations).
- Reuse `Components/Common/` — `EntityMultiSelect`, `EntityChips`, `CategoryFilterChips`. Never hand-roll profile/category selects.
- **Test-selector convention, as the page actually uses it:** form inputs carry `data-test` via `UserAttributes` (`description-input`, `key-input`, `ctrl-checkbox`); buttons carry a semantic **CSS class** (`.add-hotkey`, `.start-edit`, `.commit-edit`, `.cancel-edit`, `.show-history`, `.delete`, `.reload-hotkeys`). Follow the existing split — do not add `data-test` to buttons, and do not invent new names for hooks that already exist.
- Propagate `CancellationToken` through every async call. No `.Result` / `.Wait()`.
- FluentAssertions over raw `Assert`. Test naming `MethodName_Scenario_ExpectedResult`. AAA with blank-line separation.
- `dotnet format` needs an explicit workspace: `dotnet format AHKFlowApp.slnx`.
- `dotnet test` accepts **one** project path — run projects as separate commands, or `dotnet test AHKFlowApp.slnx` for everything.
- **This is a worktree** (`feature/wt-hotkey-ui-plan`). Commit here, never in the main checkout.
- `GenerateDocumentationFile` is on and `TreatWarningsAsErrors` is true (only CS1591 suppressed). An unresolvable `<see cref>` is CS1574 — an **error**. Reference not-yet-created types with `<c>...</c>`.
- Conventional commits, extremely concise. Atomic: one logical change per commit, feature + its tests together.

---

## File Structure

**Create (backend, Task 1):**
- `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeyKeysQuery.cs` — registry projection query + handler.
- `src/Backend/AHKFlowApp.Application/DTOs/HotkeyKeyDtos.cs` — `HotkeyKeyDto`, `HotkeyKeyCatalogDto`.
- `tests/AHKFlowApp.API.Tests/HotkeyKeysEndpointTests.cs`

**Create (frontend):**
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyActionKind.cs`, `WindowOp.cs`, `RunTargetKind.cs` — enum mirrors.
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyKeyDtos.cs` — catalog mirror.
- `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyPreviewDtos.cs` — preview request/response mirror.
- `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotkeyKeyCatalog.cs` + `IHotkeyKeyCatalog.cs` — session-cached registry + client-side key validity.
- `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs` — single-sourced labels, chip classes, per-kind summaries, combo label.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyActionChip.razor` (+ `.razor.css`) — action chip with tints.
- `src/Frontend/AHKFlowApp.UI.Blazor/Components/Common/KeyPicker.razor` — role-parameterized key autocomplete.

**Modify (frontend):**
- `DTOs/HotkeyDto.cs`, `DTOs/CreateHotkeyDto.cs`, `DTOs/UpdateHotkeyDto.cs` — typed fields.
- `DTOs/HotkeyListRequest.cs` — drop `ParametersFilter`, `Action` → `ActionKind`.
- `Services/IHotkeysApiClient.cs`, `Services/HotkeysApiClient.cs` — `GetKeysAsync`, `PreviewAsync`, filter rename.
- `Validation/HotkeyEditModel.cs` — typed fields, `IsInlineEditable`, per-kind DTO gating.
- `Components/Hotkeys/HotkeyEditDialog.razor` (+ new `.razor.css`) — full rebuild.
- `Components/Hotkeys/HotkeyMobileList.razor` — action chip + shared combo label.
- `Pages/Hotkeys.razor` — 6-column grid, inline-edit gating.
- `Program.cs` — register `IHotkeyKeyCatalog`.

**Delete:** `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyAction.cs` (backend plan line 2520 leaves this file to us).

**Tests:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/HotkeyEditDialogTests.cs`, `Components/KeyPickerTests.cs`, `Helpers/HotkeyActionDisplayTests.cs`, `Services/HotkeyKeyCatalogTests.cs`, `tests/AHKFlowApp.E2E.Tests/HotkeysCrudFlowTests.cs`
- Modify: `Pages/HotkeysPageTests.cs`, `Validation/HotkeyEditModelTests.cs`, `Services/HotkeysApiClientTests.cs`, `tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs`

---

### Task 1: Key registry endpoint

Serves the canonical registry to the picker so the UI never maintains a parallel key table. Executable **before** the backend plan lands — depends only on Wave 0's `HotkeyKeys`.

The response carries the alias map alongside the entries. The UI needs it for `IsInlineEditable` (spec decision 24): a legacy row storing `Esc` is a perfectly valid binding, and a canonical-only check would wrongly demote it to the dialog and show an error on a key AHK accepts.

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/HotkeyKeyDtos.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeyKeysQuery.cs`
- Create: `tests/AHKFlowApp.API.Tests/HotkeyKeysEndpointTests.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs` (expose `Aliases`)
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs`

**Interfaces:**
- Consumes: `HotkeyKeys.All` (`IReadOnlyList<HotkeyKeyEntry>`), `HotkeyKeyEntry(string Canonical, string Group, HotkeyKeyRoles Roles, bool RequiresBracesInSend)`, `HotkeyKeyRoles` flags — all `internal` to Application, all reachable from a handler in the same assembly.
- Produces: `HotkeyKeyDto(string Canonical, string Group, string[] Roles, bool RequiresBracesInSend)`, `HotkeyKeyCatalogDto(IReadOnlyList<HotkeyKeyDto> Keys, IReadOnlyDictionary<string,string> Aliases)`, `GET /api/v1/hotkeys/keys`.

- [ ] **Step 1: Expose the alias map**

In `src/Backend/AHKFlowApp.Application/Constants/HotkeyKeys.cs`, directly below the existing `public static IReadOnlyList<HotkeyKeyEntry> All => s_all;` (line ~117):

```csharp
    /// <summary>
    /// Accepted non-canonical spellings and the entry each resolves to. Exposed so the key
    /// picker can treat an aliased legacy value (<c>Esc</c>) as valid rather than demoting
    /// the row to the dialog with an error on a key AutoHotkey accepts.
    /// </summary>
    public static IReadOnlyDictionary<string, string> Aliases => s_aliases;
```

- [ ] **Step 2: Add the DTOs**

Create `src/Backend/AHKFlowApp.Application/DTOs/HotkeyKeyDtos.cs`:

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>One canonical key the picker may offer, with the roles it may legally play.</summary>
/// <param name="Canonical">The single spelling persisted and emitted.</param>
/// <param name="Group">Picker grouping label.</param>
/// <param name="Roles">Role names — any of HotkeyKey, ComboPrefix, SendToken, RemapSource, RemapDest.</param>
/// <param name="RequiresBracesInSend">True for named keys, which AHK requires be braced inside Send.</param>
public sealed record HotkeyKeyDto(
    string Canonical,
    string Group,
    string[] Roles,
    bool RequiresBracesInSend);

/// <summary>The whole key registry plus its accepted alias spellings.</summary>
public sealed record HotkeyKeyCatalogDto(
    IReadOnlyList<HotkeyKeyDto> Keys,
    IReadOnlyDictionary<string, string> Aliases);
```

- [ ] **Step 3: Write the failing test**

Create `tests/AHKFlowApp.API.Tests/HotkeyKeysEndpointTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests;

[Collection("SqlServer")]
public sealed class HotkeyKeysEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Fact]
    public async Task GetKeys_ReturnsRegistryWithRolesAndAliases()
    {
        HttpClient client = factory.CreateAuthenticatedClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys/keys");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyKeyCatalogDto? catalog = await response.Content.ReadFromJsonAsync<HotkeyKeyCatalogDto>();
        catalog.Should().NotBeNull();
        catalog!.Keys.Should().NotBeEmpty();
        catalog.Aliases.Should().ContainKey("Esc").WhoseValue.Should().Be("Escape");
    }

    [Fact]
    public async Task GetKeys_NamedKeyCarriesBraceFlagAndSendRole()
    {
        HttpClient client = factory.CreateAuthenticatedClient();

        HotkeyKeyCatalogDto? catalog =
            await client.GetFromJsonAsync<HotkeyKeyCatalogDto>("/api/v1/hotkeys/keys");

        HotkeyKeyDto volumeUp = catalog!.Keys.Single(k => k.Canonical == "Volume_Up");
        volumeUp.RequiresBracesInSend.Should().BeTrue();
        volumeUp.Roles.Should().Contain("SendToken");
        volumeUp.Group.Should().Be("Media & browser");
    }

    [Fact]
    public async Task GetKeys_PrintableKeyIsNotBracedInSend()
    {
        HttpClient client = factory.CreateAuthenticatedClient();

        HotkeyKeyCatalogDto? catalog =
            await client.GetFromJsonAsync<HotkeyKeyCatalogDto>("/api/v1/hotkeys/keys");

        catalog!.Keys.Single(k => k.Canonical == "c").RequiresBracesInSend.Should().BeFalse();
    }

    [Fact]
    public async Task GetKeys_RequiresAuthentication()
    {
        HttpClient client = factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys/keys");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

> Match the fixture names already used in `tests/AHKFlowApp.API.Tests` — open `HotkeysEndpointsTests.cs` and copy its factory type, collection attribute, and authenticated-client helper verbatim rather than assuming `ApiFactory`/`CreateAuthenticatedClient`.

- [ ] **Step 4: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotkeyKeysEndpointTests"
```
Expected: FAIL — 404 Not Found on `/api/v1/hotkeys/keys`.

- [ ] **Step 5: Implement the query and handler**

Create `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeyKeysQuery.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Hotkeys;

/// <summary>Returns the canonical key registry for the UI key picker. Static reference data.</summary>
public sealed record ListHotkeyKeysQuery();

internal sealed class ListHotkeyKeysQueryHandler
    : IUseCaseHandler<ListHotkeyKeysQuery, Result<HotkeyKeyCatalogDto>>
{
    // Projected once: the registry is immutable for the process lifetime.
    private static readonly HotkeyKeyCatalogDto s_catalog = Project();

    public Task<Result<HotkeyKeyCatalogDto>> ExecuteAsync(ListHotkeyKeysQuery request, CancellationToken ct) =>
        Task.FromResult(Result<HotkeyKeyCatalogDto>.Success(s_catalog));

    private static HotkeyKeyCatalogDto Project() => new(
        [.. HotkeyKeys.All.Select(e => new HotkeyKeyDto(
            e.Canonical, e.Group, RoleNames(e.Roles), e.RequiresBracesInSend))],
        HotkeyKeys.Aliases);

    // Flags -> names, excluding the None sentinel and the All aggregate so the wire format
    // lists only the five real roles.
    private static string[] RoleNames(HotkeyKeyRoles roles) =>
    [
        .. Enum.GetValues<HotkeyKeyRoles>()
            .Where(r => r is not HotkeyKeyRoles.None and not HotkeyKeyRoles.All && roles.HasFlag(r))
            .Select(r => r.ToString())
    ];
}
```

- [ ] **Step 6: Register the use case**

In `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`, add to the existing `.AddUseCase<...>()` chain alongside the other hotkey registrations:

```csharp
            .AddUseCase<ListHotkeyKeysQuery, Result<HotkeyKeyCatalogDto>, ListHotkeyKeysQueryHandler>()
```

- [ ] **Step 7: Add the controller endpoint**

In `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs`, add the dependency to the primary constructor parameter list:

```csharp
    IUseCase<ListHotkeyKeysQuery, Result<HotkeyKeyCatalogDto>> listHotkeyKeys,
```

Then add the action immediately after the existing `List` method. The route literal `keys` cannot collide with the `{id:guid}` route — a GUID constraint never matches `keys`:

```csharp
    /// <summary>Get the canonical key registry backing the hotkey key picker.</summary>
    /// <remarks>Static reference data; authorized because the controller is, not because it is user-scoped.</remarks>
    [HttpGet("keys")]
    [ProducesResponseType(typeof(HotkeyKeyCatalogDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<HotkeyKeyCatalogDto>> Keys(CancellationToken ct) =>
        (await listHotkeyKeys.ExecuteAsync(new ListHotkeyKeysQuery(), ct)).ToProblemActionResult(this);
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotkeyKeysEndpointTests"
```
Expected: PASS, 4 tests.

- [ ] **Step 9: Format and commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Backend tests/AHKFlowApp.API.Tests
git commit -m "feat: serve hotkey key registry for UI picker"
```

---

### Task 2: Frontend contract mirrors

Re-mirrors the hotkey DTOs onto the typed model and deletes the obsolete `HotkeyAction` mirror. Pure contract change — the page and dialog still reference the old members, so **this task deliberately leaves the project not compiling**; Task 5 closes it. Do not attempt a green build until Task 5.

> **Requires backend Task 6 complete.** Copy the field order from the backend's `HotkeyDto` verbatim; a mismatch deserializes silently wrong for positional records.

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyActionKind.cs`, `WindowOp.cs`, `RunTargetKind.cs`, `HotkeyKeyDtos.cs`, `HotkeyPreviewDtos.cs`
- Modify: `DTOs/HotkeyDto.cs`, `DTOs/CreateHotkeyDto.cs`, `DTOs/UpdateHotkeyDto.cs`, `DTOs/HotkeyListRequest.cs`
- Delete: `DTOs/HotkeyAction.cs`

**Interfaces:**
- Consumes: backend `HotkeyDto`/`CreateHotkeyDto`/`UpdateHotkeyDto` (backend plan Task 6), `HotkeyPreviewRequestDto`/`HotkeyPreviewDto` (backend plan Task 9), `HotkeyKeyCatalogDto` (Task 1).
- Produces: the frontend mirrors every later task binds against.

- [ ] **Step 1: Add the enum mirrors**

Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyActionKind.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>What a hotkey does. Mirror of the backend enum — order is the wire contract.</summary>
public enum HotkeyActionKind
{
    SendText = 0,
    SendKeys = 1,
    Run = 2,
    Window = 3,
    Remap = 4,
    Disable = 5,
    Raw = 6,
}
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/WindowOp.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>Window operation a Window-kind hotkey performs. Mirror of the backend enum.</summary>
public enum WindowOp
{
    Minimize = 0,
    Maximize = 1,
    Restore = 2,
    Close = 3,
    ToggleAlwaysOnTop = 4,
}
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/RunTargetKind.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>Display label for a Run target. Does not change emission. Mirror of the backend enum.</summary>
public enum RunTargetKind
{
    Application = 0,
    Url = 1,
    Folder = 2,
}
```

> Open the backend enums created by backend plan Task 1 and confirm each member's explicit value matches. These are the wire contract.

- [ ] **Step 2: Add the catalog and preview mirrors**

Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyKeyDtos.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>One canonical key the picker may offer. Mirror of the backend DTO.</summary>
public sealed record HotkeyKeyDto(
    string Canonical,
    string Group,
    string[] Roles,
    bool RequiresBracesInSend);

/// <summary>The key registry plus its accepted alias spellings. Mirror of the backend DTO.</summary>
public sealed record HotkeyKeyCatalogDto(
    IReadOnlyList<HotkeyKeyDto> Keys,
    IReadOnlyDictionary<string, string> Aliases);
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyPreviewDtos.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>Draft hotkey fields to preview, without saving. Mirror of the backend DTO.</summary>
public sealed record HotkeyPreviewRequestDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null);

/// <summary>The AutoHotkey snippet a hotkey draft would generate. Mirror of the backend DTO.</summary>
public sealed record HotkeyPreviewDto(string Snippet);
```

- [ ] **Step 3: Retype the hotkey DTOs**

Replace `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyDto.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotkeyDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyActionKind ActionKind,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[]? CategoryIds = null);
```

Replace `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotkeyDto.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CreateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    Guid[]? CategoryIds = null);
```

Replace `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotkeyDto.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record UpdateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    Guid[]? CategoryIds = null);
```

> Field order must match the backend records exactly. Read the backend files before writing these — do not trust the order above if it disagrees with what backend Task 6 produced.

- [ ] **Step 4: Retype the list request**

In `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyListRequest.cs`, delete the `ParametersFilter` parameter and replace `HotkeyAction? Action = null` with `HotkeyActionKind? ActionKind = null`. Backend Task 6 dropped both the `parametersFilter` query parameter and the `"parameters"`/`"action"` sort keys, so leaving them here would send parameters the API rejects.

- [ ] **Step 5: Delete the obsolete mirror**

```bash
git rm src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyAction.cs
```

- [ ] **Step 6: Commit (build is intentionally red)**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs
git commit -m "refactor: mirror typed hotkey action DTOs in frontend"
```

---

### Task 3: API client methods

Adds the two calls the picker and preview panel need, and re-points the list filter.

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeysApiClient.cs`, `Services/HotkeysApiClient.cs`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs`

**Interfaces:**
- Consumes: `ApiClientBase.SendAsync<T>`, `HotkeyKeyCatalogDto`, `HotkeyPreviewRequestDto`, `HotkeyPreviewDto`.
- Produces: `IHotkeysApiClient.GetKeysAsync(CancellationToken)` → `Task<ApiResult<HotkeyKeyCatalogDto>>`; `IHotkeysApiClient.PreviewAsync(HotkeyPreviewRequestDto, CancellationToken)` → `Task<ApiResult<HotkeyPreviewDto>>`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs`, following the existing handler-stub pattern in that file:

```csharp
    [Fact]
    public async Task GetKeysAsync_RequestsKeysRoute()
    {
        var handler = new StubHandler(JsonSerializer.Serialize(new HotkeyKeyCatalogDto(
            [new HotkeyKeyDto("F1", "Function keys", ["HotkeyKey"], true)],
            new Dictionary<string, string> { ["Esc"] = "Escape" })));
        var client = new HotkeysApiClient(handler.CreateClient());

        ApiResult<HotkeyKeyCatalogDto> result = await client.GetKeysAsync();

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().EndWith("api/v1/hotkeys/keys");
        result.Value!.Keys.Should().ContainSingle(k => k.Canonical == "F1");
    }

    [Fact]
    public async Task PreviewAsync_PostsDraftToPreviewRoute()
    {
        var handler = new StubHandler(JsonSerializer.Serialize(new HotkeyPreviewDto("#n::Run(\"notepad\")")));
        var client = new HotkeysApiClient(handler.CreateClient());

        ApiResult<HotkeyPreviewDto> result = await client.PreviewAsync(new HotkeyPreviewRequestDto(
            "Open Notepad", "n", HotkeyActionKind.Run, Win: true,
            RunTarget: "notepad", RunTargetKind: RunTargetKind.Application));

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().EndWith("api/v1/hotkeys/preview");
        result.Value!.Snippet.Should().Be("#n::Run(\"notepad\")");
    }
```

> Open the existing file first and reuse whatever stub-handler helper it already defines. Do not introduce a second stub type.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysApiClientTests"
```
Expected: FAIL — `GetKeysAsync` / `PreviewAsync` not defined.

- [ ] **Step 3: Extend the interface**

In `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeysApiClient.cs`, add:

```csharp
    Task<ApiResult<HotkeyKeyCatalogDto>> GetKeysAsync(CancellationToken ct = default);
    Task<ApiResult<HotkeyPreviewDto>> PreviewAsync(HotkeyPreviewRequestDto request, CancellationToken ct = default);
```

- [ ] **Step 4: Implement**

In `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotkeysApiClient.cs`, add:

```csharp
    public Task<ApiResult<HotkeyKeyCatalogDto>> GetKeysAsync(CancellationToken ct = default) =>
        SendAsync<HotkeyKeyCatalogDto>(HttpMethod.Get, $"{BasePath}/keys", null, ct);

    public Task<ApiResult<HotkeyPreviewDto>> PreviewAsync(HotkeyPreviewRequestDto request, CancellationToken ct = default) =>
        SendAsync<HotkeyPreviewDto>(HttpMethod.Post, $"{BasePath}/preview", JsonContent.Create(request), ct);
```

In the same file's `ListAsync`, delete the `Add(parts, "parametersFilter", request.ParametersFilter);` line and replace the `request.Action` block with:

```csharp
        if (request.ActionKind.HasValue)
            parts.Add($"actionKind={Uri.EscapeDataString(request.ActionKind.Value.ToString())}");
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysApiClientTests"
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Services tests/AHKFlowApp.UI.Blazor.Tests/Services
git commit -m "feat: add hotkey keys + preview api client methods"
```

---

### Task 4: Key catalog service

Session-scoped cache over the keys endpoint, plus the client-side key-validity check that `IsInlineEditable` needs. This is the **only** client-side key logic in the plan: membership against the fetched registry, the alias map, and the `vk`/`sc` shape. The five role *grammars* stay server-side.

> The `vk`/`sc` regexes below are copied from the landed `HotkeyKeys.cs:66-70` — `vk` is `{1,2}`, `sc` is `{1,3}`. Spec §8 says `sc[0-9a-f]{1,4}`; the shipped code says `{1,3}` and pads to width 3. **Mirror the code, not the spec** — this client check must agree with the server that will accept or reject the value. The discrepancy is logged as an open question at the end of this plan.

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeyKeyCatalog.cs`, `Services/HotkeyKeyCatalog.cs`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeyKeyCatalogTests.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

**Interfaces:**
- Consumes: `IHotkeysApiClient.GetKeysAsync` (Task 3).
- Produces: `IHotkeyKeyCatalog` with `ValueTask<IReadOnlyList<HotkeyKeyDto>> ForRoleAsync(string role, CancellationToken ct)`, `bool IsValidKey(string? key)`, `string? GroupOf(string? canonical)`, `bool RequiresBracesInSend(string? canonical)`, `bool IsLoaded { get; }`.

The catalog **indexes on load** rather than scanning per call: `IsValidKey` runs once per grid row per render (50 rows × ~100 entries is 5 000 string comparisons a frame in WASM), and `GroupOf` runs once per rendered picker item. Both become dictionary lookups. Rebuilding both maps with `StringComparer.OrdinalIgnoreCase` at the same time also settles alias casing — `System.Text.Json` deserializes into an ordinal dictionary, so `esc` would otherwise miss where `Esc` hits.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeyKeyCatalogTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotkeyKeyCatalogTests
{
    private static readonly HotkeyKeyCatalogDto Sample = new(
        [
            new HotkeyKeyDto("F1", "Function keys", ["HotkeyKey", "SendToken", "RemapSource", "RemapDest"], true),
            new HotkeyKeyDto("c", "Letters & digits", ["HotkeyKey", "SendToken"], false),
            new HotkeyKeyDto("WheelUp", "Mouse", ["HotkeyKey", "SendToken"], true),
        ],
        new Dictionary<string, string> { ["Esc"] = "Escape" });

    private static IHotkeysApiClient ApiReturning(HotkeyKeyCatalogDto catalog)
    {
        IHotkeysApiClient api = Substitute.For<IHotkeysApiClient>();
        api.GetKeysAsync(Arg.Any<CancellationToken>()).Returns(ApiResult<HotkeyKeyCatalogDto>.Ok(catalog));
        return api;
    }

    [Fact]
    public async Task ForRoleAsync_ReturnsOnlyKeysCarryingThatRole()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));

        IReadOnlyList<HotkeyKeyDto> remapDests = await catalog.ForRoleAsync("RemapDest", CancellationToken.None);

        remapDests.Should().ContainSingle().Which.Canonical.Should().Be("F1");
    }

    [Fact]
    public async Task ForRoleAsync_FetchesOnceAcrossRepeatedCalls()
    {
        IHotkeysApiClient api = ApiReturning(Sample);
        var catalog = new HotkeyKeyCatalog(api);

        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);
        await catalog.ForRoleAsync("SendToken", CancellationToken.None);

        await api.Received(1).GetKeysAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task GroupOf_ReturnsTheEntrysPickerGroup()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.GroupOf("Volume_Up").Should().Be("Media & browser");
        catalog.GroupOf("vk1B").Should().BeNull();
    }

    [Fact]
    public async Task RequiresBracesInSend_ReadsTheRegistryFlag()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("SendToken", CancellationToken.None);

        catalog.RequiresBracesInSend("F1").Should().BeTrue();
        catalog.RequiresBracesInSend("c").Should().BeFalse();

        // Not a registry name: vk/sc codes must still be braced inside a Send token.
        catalog.RequiresBracesInSend("vk1B").Should().BeTrue();
    }

    [Theory]
    [InlineData("F1")]
    [InlineData("f1")]
    [InlineData("Esc")]
    [InlineData("esc")]
    [InlineData("vk1B")]
    [InlineData("sc001")]
    public async Task IsValidKey_AcceptsRegistryAliasAndCodes(string key)
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.IsValidKey(key).Should().BeTrue();
    }

    [Theory]
    [InlineData("zzz")]
    [InlineData("vk00")]
    [InlineData("sc000")]
    [InlineData("vk1Bsc001")]
    [InlineData("")]
    [InlineData(null)]
    public async Task IsValidKey_RejectsUnknownZeroAndCombinedCodes(string? key)
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.IsValidKey(key).Should().BeFalse();
    }

    [Fact]
    public void IsValidKey_BeforeLoad_IsOptimistic()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));

        catalog.IsValidKey("anything at all").Should().BeTrue();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyKeyCatalogTests"
```
Expected: FAIL — `HotkeyKeyCatalog` not defined.

- [ ] **Step 3: Implement the interface**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeyKeyCatalog.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>
/// Session cache over the server's canonical key registry, plus the key-validity check the
/// grid uses to decide inline-edit eligibility.
/// </summary>
public interface IHotkeyKeyCatalog
{
    /// <summary>True once the registry has been fetched at least once.</summary>
    bool IsLoaded { get; }

    /// <summary>
    /// Keys legal in the given role, ordered by picker group then name, fetching the registry
    /// on first call. The ordering is what makes groups cluster in the picker's dropdown —
    /// MudAutocomplete 9.3.0 has no group-header support, so order plus a per-item group label
    /// is how grouping is conveyed.
    /// </summary>
    ValueTask<IReadOnlyList<HotkeyKeyDto>> ForRoleAsync(string role, CancellationToken ct = default);

    /// <summary>
    /// Whether a stored key would pass server-side key validation. Optimistic before the
    /// registry loads — a row must never be demoted to the dialog merely because the catalog
    /// has not arrived yet.
    /// </summary>
    bool IsValidKey(string? key);

    /// <summary>Picker group for a canonical registry name, or null for a vk/sc code or unknown name.</summary>
    string? GroupOf(string? canonical);

    /// <summary>
    /// Whether this key must be braced inside a Send token. True for named registry entries
    /// ({Volume_Up}) and for vk/sc codes ({vk1B}); false for a single printable character (c).
    /// Not meaningful for a remap destination, which is never braced.
    /// </summary>
    bool RequiresBracesInSend(string? canonical);
}
```

- [ ] **Step 4: Implement the service**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotkeyKeyCatalog.cs`:

```csharp
using System.Text.RegularExpressions;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <inheritdoc cref="IHotkeyKeyCatalog"/>
public sealed partial class HotkeyKeyCatalog(IHotkeysApiClient api) : IHotkeyKeyCatalog
{
    // Copied from AHKFlowApp.Application.Constants.HotkeyKeys — vk is two hex digits, sc is
    // three. Anchored \A..\z, not ^..$: .NET's $ also matches before a trailing newline, so
    // "vk1\n" would otherwise pass and split the emitted left-hand side across two lines.
    [GeneratedRegex(@"\Avk[0-9a-f]{1,2}\z", RegexOptions.IgnoreCase)]
    private static partial Regex VirtualKey();

    [GeneratedRegex(@"\Asc[0-9a-f]{1,3}\z", RegexOptions.IgnoreCase)]
    private static partial Regex ScanCode();

    private readonly SemaphoreSlim _gate = new(1, 1);
    private HotkeyKeyCatalogDto? _catalog;

    // Built once on load. IsValidKey runs per grid row per render and GroupOf runs per rendered
    // picker item, so neither may scan the ~100-entry list. Both maps are OrdinalIgnoreCase,
    // which also matches the server's case-insensitive alias and name lookups — System.Text.Json
    // would otherwise hand back an ordinal dictionary in which "esc" misses and "Esc" hits.
    private Dictionary<string, HotkeyKeyDto> _byName = new(StringComparer.OrdinalIgnoreCase);
    private Dictionary<string, string> _aliases = new(StringComparer.OrdinalIgnoreCase);

    public bool IsLoaded => _catalog is not null;

    public async ValueTask<IReadOnlyList<HotkeyKeyDto>> ForRoleAsync(string role, CancellationToken ct = default)
    {
        HotkeyKeyCatalogDto catalog = await LoadAsync(ct);
        return
        [
            .. catalog.Keys
                .Where(k => k.Roles.Contains(role, StringComparer.Ordinal))
                .OrderBy(k => k.Group, StringComparer.Ordinal)
                .ThenBy(k => k.Canonical, StringComparer.OrdinalIgnoreCase)
        ];
    }

    public bool IsValidKey(string? key)
    {
        // Optimistic before load: see the interface remark.
        if (_catalog is null)
            return true;

        if (string.IsNullOrWhiteSpace(key))
            return false;

        if (_aliases.ContainsKey(key) || _byName.ContainsKey(key))
            return true;

        // A code naming no key (vk00, sc000) is rejected server-side; the digit-count regex
        // cannot express "hex, but not all zero", so it is checked separately here too.
        if (IsCode(key))
            return key[2..].Any(c => c != '0');

        return false;
    }

    public string? GroupOf(string? canonical) =>
        canonical is not null && _byName.TryGetValue(canonical, out HotkeyKeyDto? entry) ? entry.Group : null;

    public bool RequiresBracesInSend(string? canonical)
    {
        if (canonical is null)
            return false;

        if (_byName.TryGetValue(canonical, out HotkeyKeyDto? entry))
            return entry.RequiresBracesInSend;

        // Off-registry values reaching a Send token are vk/sc codes, which AHK requires braced:
        // Send "vk1B" types the four literal characters, Send "{vk1B}" presses the key.
        return IsCode(canonical);
    }

    private static bool IsCode(string value) => VirtualKey().IsMatch(value) || ScanCode().IsMatch(value);

    private async ValueTask<HotkeyKeyCatalogDto> LoadAsync(CancellationToken ct)
    {
        if (_catalog is { } cached)
            return cached;

        await _gate.WaitAsync(ct);
        try
        {
            if (_catalog is { } raced)
                return raced;

            ApiResult<HotkeyKeyCatalogDto> result = await api.GetKeysAsync(ct);

            // A failed fetch is not cached: the picker renders empty and the next dialog
            // open retries, rather than permanently offering no keys for the session.
            if (!result.IsSuccess || result.Value is null)
                return new HotkeyKeyCatalogDto([], new Dictionary<string, string>());

            _catalog = result.Value;
            _byName = result.Value.Keys.ToDictionary(k => k.Canonical, StringComparer.OrdinalIgnoreCase);
            _aliases = new Dictionary<string, string>(result.Value.Aliases, StringComparer.OrdinalIgnoreCase);
            return _catalog;
        }
        finally
        {
            _gate.Release();
        }
    }
}
```

- [ ] **Step 5: Register the service**

In `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, alongside the other API-client registrations:

```csharp
builder.Services.AddScoped<IHotkeyKeyCatalog, HotkeyKeyCatalog>();
```

Scoped, not singleton: in Blazor WebAssembly the container lives for the whole app session, so scoped already gives one instance per session and keeps the lifetime consistent with the `IHotkeysApiClient` it depends on.

- [ ] **Step 6: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyKeyCatalogTests"
```
Expected: PASS, 17 tests.

- [ ] **Step 7: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Services src/Frontend/AHKFlowApp.UI.Blazor/Program.cs tests/AHKFlowApp.UI.Blazor.Tests/Services
git commit -m "feat: add session-cached hotkey key catalog"
```

---

### Task 5: Typed edit model

Retypes `HotkeyEditModel` and restores a green build. Two behaviours matter beyond the field swap:

1. **Per-kind fields are retained in the model and nulled only on the wire.** Server validation is both-or-neither — a `RunTarget` sent while `ActionKind` is `SendText` is a 400. Gating at DTO-build time (rather than clearing on kind switch) means Run → SendText → Run restores what the user typed, and one method owns the gating rule.
2. **`IsInlineEditable` includes key validity**, which is how legacy rows with un-migratable keys route themselves to the dialog with no new UI (spec decision 24).

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotkeyEditModel.cs`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Validation/HotkeyEditModelTests.cs`

**Interfaces:**
- Consumes: typed DTOs (Task 2), `IHotkeyKeyCatalog.IsValidKey` (Task 4).
- Produces: `HotkeyEditModel` with `ActionKind`, `Text`, `SendKeysContent`, `RunTarget`, `RunTargetKind`, `WindowOp`, `RemapDest`, `Body`; `IsInlineEditable(IHotkeyKeyCatalog)`; `ToCreateDto()`, `ToUpdateDto()`, `ToPreviewRequest()`.

- [ ] **Step 1: Write the failing tests**

Replace the body of `tests/AHKFlowApp.UI.Blazor.Tests/Validation/HotkeyEditModelTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Validation;

public sealed class HotkeyEditModelTests
{
    private static IHotkeyKeyCatalog CatalogSaying(bool valid)
    {
        IHotkeyKeyCatalog catalog = Substitute.For<IHotkeyKeyCatalog>();
        catalog.IsValidKey(Arg.Any<string?>()).Returns(valid);
        return catalog;
    }

    [Fact]
    public void ToCreateDto_NullsFieldsBelongingToOtherKinds()
    {
        var model = new HotkeyEditModel
        {
            Description = "Open Notepad",
            Key = "n",
            Win = true,
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "notepad",
            RunTargetKind = RunTargetKind.Application,
            Text = "stale text from a previous kind",
            Body = "stale body",
        };

        CreateHotkeyDto dto = model.ToCreateDto();

        dto.ActionKind.Should().Be(HotkeyActionKind.Run);
        dto.RunTarget.Should().Be("notepad");
        dto.Text.Should().BeNull();
        dto.Body.Should().BeNull();
    }

    [Fact]
    public void ToCreateDto_RetainsOtherKindFieldsOnTheModel()
    {
        var model = new HotkeyEditModel
        {
            Description = "Open Notepad",
            Key = "n",
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "notepad",
            Text = "typed earlier",
        };

        _ = model.ToCreateDto();

        model.Text.Should().Be("typed earlier");
    }

    [Fact]
    public void ToCreateDto_DisableKindSendsNoActionFields()
    {
        var model = new HotkeyEditModel { Description = "Kill F1", Key = "F1", ActionKind = HotkeyActionKind.Disable };

        CreateHotkeyDto dto = model.ToCreateDto();

        dto.Text.Should().BeNull();
        dto.SendKeysContent.Should().BeNull();
        dto.RunTarget.Should().BeNull();
        dto.RunTargetKind.Should().BeNull();
        dto.WindowOp.Should().BeNull();
        dto.RemapDest.Should().BeNull();
        dto.Body.Should().BeNull();
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, true)]
    [InlineData(HotkeyActionKind.Run, true)]
    [InlineData(HotkeyActionKind.SendKeys, false)]
    [InlineData(HotkeyActionKind.Window, false)]
    [InlineData(HotkeyActionKind.Remap, false)]
    [InlineData(HotkeyActionKind.Disable, false)]
    [InlineData(HotkeyActionKind.Raw, false)]
    public void IsInlineEditable_OnlySendTextAndRun(HotkeyActionKind kind, bool expected)
    {
        var model = new HotkeyEditModel { Key = "n", ActionKind = kind };

        model.IsInlineEditable(CatalogSaying(valid: true)).Should().Be(expected);
    }

    [Fact]
    public void IsInlineEditable_FalseWhenKeyFailsValidation()
    {
        var model = new HotkeyEditModel { Key = "!!legacy!!", ActionKind = HotkeyActionKind.Run };

        model.IsInlineEditable(CatalogSaying(valid: false)).Should().BeFalse();
    }

    [Fact]
    public void ToPreviewRequest_CarriesActiveKindFieldsOnly()
    {
        var model = new HotkeyEditModel
        {
            Description = "Volume",
            Key = "p",
            Win = true,
            ActionKind = HotkeyActionKind.SendKeys,
            SendKeysContent = "{Media_Play_Pause}",
            RunTarget = "stale",
        };

        HotkeyPreviewRequestDto request = model.ToPreviewRequest();

        request.SendKeysContent.Should().Be("{Media_Play_Pause}");
        request.RunTarget.Should().BeNull();
    }

    [Fact]
    public void FromDto_RoundTripsTypedFields()
    {
        var dto = new HotkeyDto(
            Guid.NewGuid(), [], true, "Always on top", "Space",
            Ctrl: true, Alt: false, Shift: false, Win: false,
            HotkeyActionKind.Window, null, null, null, null, WindowOp.ToggleAlwaysOnTop, null, null,
            DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);

        HotkeyEditModel model = HotkeyEditModel.FromDto(dto);

        model.ActionKind.Should().Be(HotkeyActionKind.Window);
        model.WindowOp.Should().Be(WindowOp.ToggleAlwaysOnTop);
        model.Ctrl.Should().BeTrue();
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyEditModelTests"
```
Expected: FAIL to compile — `ActionKind` not defined on `HotkeyEditModel`.

- [ ] **Step 3: Retype the model**

Replace `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotkeyEditModel.cs`:

```csharp
using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotkeyEditModel
{
    public const int TextMaxLength = 4_000;
    public const int BodyMaxLength = 4_000;
    public const int RunTargetMaxLength = 500;

    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Description is required.")]
    [MaxLength(200, ErrorMessage = "Description must be 200 characters or fewer.")]
    public string Description { get; set; } = "";

    [Required(ErrorMessage = "Key is required.")]
    [MaxLength(20, ErrorMessage = "Key must be 20 characters or fewer.")]
    public string Key { get; set; } = "";

    public bool Ctrl { get; set; }
    public bool Alt { get; set; }
    public bool Shift { get; set; }
    public bool Win { get; set; }

    public HotkeyActionKind ActionKind { get; set; } = HotkeyActionKind.SendText;

    // Per-kind fields. All are retained across kind switches so a user who toggles away and
    // back does not lose typed work; gating to the active kind happens once, on the wire, in
    // ToCreateDto / ToUpdateDto / ToPreviewRequest. Server validation is both-or-neither, so
    // sending a field belonging to an inactive kind is a 400.
    public string? Text { get; set; }
    public string? SendKeysContent { get; set; }
    public string? RunTarget { get; set; }
    public RunTargetKind? RunTargetKind { get; set; }
    public WindowOp? WindowOp { get; set; }
    public string? RemapDest { get; set; }
    public string? Body { get; set; }

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];
    public List<Guid> CategoryIds { get; set; } = [];

    /// <summary>
    /// Grid rows offer inline edit only for the two kinds whose whole payload is a single text
    /// field, and only when the key would survive server-side validation. The key clause is what
    /// surfaces legacy rows the action migration could not rewrite: they route to the dialog,
    /// where the existing field-level error already appears on open. No extra UI, per spec §8.
    /// </summary>
    public bool IsInlineEditable(IHotkeyKeyCatalog catalog) =>
        ActionKind is HotkeyActionKind.SendText or HotkeyActionKind.Run
        && catalog.IsValidKey(Key);

    public static HotkeyEditModel FromDto(HotkeyDto dto) => new()
    {
        Id = dto.Id,
        Description = dto.Description,
        Key = dto.Key,
        Ctrl = dto.Ctrl,
        Alt = dto.Alt,
        Shift = dto.Shift,
        Win = dto.Win,
        ActionKind = dto.ActionKind,
        Text = dto.Text,
        SendKeysContent = dto.SendKeysContent,
        RunTarget = dto.RunTarget,
        RunTargetKind = dto.RunTargetKind,
        WindowOp = dto.WindowOp,
        RemapDest = dto.RemapDest,
        Body = dto.Body,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
        CategoryIds = [.. dto.CategoryIds ?? []],
    };

    public HotkeyEditModel Clone() => new()
    {
        Id = Id,
        Description = Description,
        Key = Key,
        Ctrl = Ctrl,
        Alt = Alt,
        Shift = Shift,
        Win = Win,
        ActionKind = ActionKind,
        Text = Text,
        SendKeysContent = SendKeysContent,
        RunTarget = RunTarget,
        RunTargetKind = RunTargetKind,
        WindowOp = WindowOp,
        RemapDest = RemapDest,
        Body = Body,
        AppliesToAllProfiles = AppliesToAllProfiles,
        ProfileIds = [.. ProfileIds],
        CategoryIds = [.. CategoryIds],
    };

    public CreateHotkeyDto ToCreateDto()
    {
        ActionFields f = ActiveFields();
        return new(Description, Key, ActionKind, Ctrl, Alt, Shift, Win,
            f.Text, f.SendKeysContent, f.RunTarget, f.RunTargetKind, f.WindowOp, f.RemapDest, f.Body,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, [.. CategoryIds]);
    }

    public UpdateHotkeyDto ToUpdateDto()
    {
        ActionFields f = ActiveFields();
        return new(Description, Key, ActionKind, Ctrl, Alt, Shift, Win,
            f.Text, f.SendKeysContent, f.RunTarget, f.RunTargetKind, f.WindowOp, f.RemapDest, f.Body,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, [.. CategoryIds]);
    }

    public HotkeyPreviewRequestDto ToPreviewRequest()
    {
        ActionFields f = ActiveFields();
        return new(Description, Key, ActionKind, Ctrl, Alt, Shift, Win,
            f.Text, f.SendKeysContent, f.RunTarget, f.RunTargetKind, f.WindowOp, f.RemapDest, f.Body);
    }

    /// <summary>The single place that knows which fields each kind owns.</summary>
    private ActionFields ActiveFields() => ActionKind switch
    {
        HotkeyActionKind.SendText => new() { Text = Text },
        HotkeyActionKind.SendKeys => new() { SendKeysContent = SendKeysContent },
        HotkeyActionKind.Run => new() { RunTarget = RunTarget, RunTargetKind = RunTargetKind },
        HotkeyActionKind.Window => new() { WindowOp = WindowOp },
        HotkeyActionKind.Remap => new() { RemapDest = RemapDest },
        HotkeyActionKind.Disable => new(),
        HotkeyActionKind.Raw => new() { Body = Body },
        _ => new(),
    };

    private sealed record ActionFields
    {
        public string? Text { get; init; }
        public string? SendKeysContent { get; init; }
        public string? RunTarget { get; init; }
        public RunTargetKind? RunTargetKind { get; init; }
        public WindowOp? WindowOp { get; init; }
        public string? RemapDest { get; init; }
        public string? Body { get; init; }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyEditModelTests"
```
Expected: PASS, 13 tests. The Hotkeys page and dialog still reference removed members and will not compile — expected until Tasks 8 and 9.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Validation tests/AHKFlowApp.UI.Blazor.Tests/Validation
git commit -m "refactor: retype HotkeyEditModel onto typed actions"
```

---

### Task 6: Action display helper and chip

The single source of action presentation, so the desktop grid and mobile list cannot drift. It absorbs `HotkeyMobileList`'s local `FormatCombo` — that helper existing in one branch only is exactly the drift this task exists to prevent.

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyActionChip.razor`, `HotkeyActionChip.razor.css`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HotkeyActionDisplayTests.cs`

**Interfaces:**
- Consumes: `HotkeyActionKind`, `WindowOp`, `RunTargetKind`, `HotkeyEditModel`.
- Produces: `HotkeyActionDisplay.Label(kind)`, `.ChipClass(kind)`, `.Icon(kind)`, `.Summary(model)`, `.ComboLabel(model)`, `.RawWarningText`; `<HotkeyActionChip Kind="..." />`.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Helpers/HotkeyActionDisplayTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class HotkeyActionDisplayTests
{
    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Send text")]
    [InlineData(HotkeyActionKind.SendKeys, "Send keys")]
    [InlineData(HotkeyActionKind.Run, "Run")]
    [InlineData(HotkeyActionKind.Window, "Window")]
    [InlineData(HotkeyActionKind.Remap, "Remap")]
    [InlineData(HotkeyActionKind.Disable, "Disable")]
    [InlineData(HotkeyActionKind.Raw, "Raw")]
    public void Label_IsHumanReadablePerKind(HotkeyActionKind kind, string expected) =>
        HotkeyActionDisplay.Label(kind).Should().Be(expected);

    [Theory]
    [InlineData(false, false, false, false, "n", "n")]
    [InlineData(true, false, false, false, "c", "Ctrl+C")]
    [InlineData(true, true, false, false, "s", "Ctrl+Alt+S")]
    [InlineData(false, false, false, true, "n", "Win+N")]
    [InlineData(true, true, true, true, "Space", "Ctrl+Alt+Shift+Win+Space")]
    public void ComboLabel_OrdersModifiersCtrlAltShiftWin(
        bool ctrl, bool alt, bool shift, bool win, string key, string expected)
    {
        var model = new HotkeyEditModel { Ctrl = ctrl, Alt = alt, Shift = shift, Win = win, Key = key };

        HotkeyActionDisplay.ComboLabel(model).Should().Be(expected);
    }

    [Fact]
    public void Summary_SendText_IsFirstLineWithEllipsis()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.SendText, Text = "Jane Smith\nAcme" };

        HotkeyActionDisplay.Summary(model).Should().Be("Jane Smith…");
    }

    [Fact]
    public void Summary_Run_IsTarget()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Run, RunTarget = "notepad" };

        HotkeyActionDisplay.Summary(model).Should().Be("notepad");
    }

    [Fact]
    public void Summary_Window_IsOperationLabel()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Window, WindowOp = WindowOp.ToggleAlwaysOnTop };

        HotkeyActionDisplay.Summary(model).Should().Be("Toggle always on top");
    }

    [Fact]
    public void Summary_Remap_ShowsDestination()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Remap, RemapDest = "Ctrl" };

        HotkeyActionDisplay.Summary(model).Should().Be("acts as Ctrl");
    }

    [Fact]
    public void Summary_Disable_IsFixedPhrase()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Disable };

        HotkeyActionDisplay.Summary(model).Should().Be("does nothing");
    }

    [Fact]
    public void Summary_Raw_IsFirstBodyLine()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Raw, Body = "  MsgBox \"hi\"\n  Sleep 100" };

        HotkeyActionDisplay.Summary(model).Should().Be("MsgBox \"hi\"…");
    }

    [Fact]
    public void Summary_MissingPayload_IsEmDash()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Run, RunTarget = null };

        HotkeyActionDisplay.Summary(model).Should().Be("—");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyActionDisplayTests"
```
Expected: FAIL — `HotkeyActionDisplay` not defined.

- [ ] **Step 3: Implement the helper**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/HotkeyActionDisplay.cs`:

```csharp
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using MudBlazor;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// Single-sourced label, icon, tint and summary for a hotkey's action, plus the modifier/key
/// combo label. Shared by the desktop grid and the mobile list so the two branches cannot drift.
/// </summary>
internal static class HotkeyActionDisplay
{
    /// <summary>
    /// Warning conveyed to assistive tech and sighted users alike — the chip's warning colour
    /// and icon alone are not exposed to screen readers. Wording is fixed by spec §5: Raw is
    /// not sandboxed, and a syntax error aborts the whole generated profile, not one binding.
    /// </summary>
    public const string RawWarningText =
        "Raw is unchecked AutoHotkey. A mistake here can stop the whole profile script from loading.";

    public static string Label(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => "Send text",
        HotkeyActionKind.SendKeys => "Send keys",
        HotkeyActionKind.Run => "Run",
        HotkeyActionKind.Window => "Window",
        HotkeyActionKind.Remap => "Remap",
        HotkeyActionKind.Disable => "Disable",
        HotkeyActionKind.Raw => "Raw",
        _ => kind.ToString(),
    };

    public static string ChipClass(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => "action-chip--sendtext",
        HotkeyActionKind.SendKeys => "action-chip--sendkeys",
        HotkeyActionKind.Run => "action-chip--run",
        HotkeyActionKind.Window => "action-chip--window",
        HotkeyActionKind.Remap => "action-chip--remap",
        HotkeyActionKind.Disable => "action-chip--disable",
        HotkeyActionKind.Raw => "action-chip--raw",
        _ => "action-chip--sendtext",
    };

    public static string Icon(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => Icons.Material.Filled.TextFields,
        HotkeyActionKind.SendKeys => Icons.Material.Filled.Keyboard,
        HotkeyActionKind.Run => Icons.Material.Filled.PlayArrow,
        HotkeyActionKind.Window => Icons.Material.Filled.Window,
        HotkeyActionKind.Remap => Icons.Material.Filled.SwapHoriz,
        HotkeyActionKind.Disable => Icons.Material.Filled.Block,
        HotkeyActionKind.Raw => Icons.Material.Filled.Warning,
        _ => Icons.Material.Filled.TextFields,
    };

    public static string WindowOpLabel(WindowOp op) => op switch
    {
        DTOs.WindowOp.Minimize => "Minimize",
        DTOs.WindowOp.Maximize => "Maximize",
        DTOs.WindowOp.Restore => "Restore",
        DTOs.WindowOp.Close => "Close",
        DTOs.WindowOp.ToggleAlwaysOnTop => "Toggle always on top",
        _ => op.ToString(),
    };

    public static string RunTargetKindLabel(RunTargetKind kind) => kind switch
    {
        DTOs.RunTargetKind.Application => "Application",
        DTOs.RunTargetKind.Url => "URL",
        DTOs.RunTargetKind.Folder => "Folder",
        _ => kind.ToString(),
    };

    /// <summary>
    /// Compact modifier + key label, e.g. <c>Ctrl+Alt+S</c>. Modifier order is fixed
    /// Ctrl, Alt, Shift, Win so two rows with the same binding always read identically.
    /// Single-character keys are upper-cased for legibility; named keys keep their spelling.
    /// </summary>
    public static string ComboLabel(HotkeyEditModel item)
    {
        List<string> parts = [];
        if (item.Ctrl) parts.Add("Ctrl");
        if (item.Alt) parts.Add("Alt");
        if (item.Shift) parts.Add("Shift");
        if (item.Win) parts.Add("Win");

        string key = item.Key.Length == 1 ? item.Key.ToUpperInvariant() : item.Key;
        parts.Add(key);

        return string.Join("+", parts);
    }

    /// <summary>One-line summary of the action's payload for the grid and mobile list.</summary>
    public static string Summary(HotkeyEditModel item) => item.ActionKind switch
    {
        HotkeyActionKind.SendText => FirstLine(item.Text),
        HotkeyActionKind.SendKeys => Plain(item.SendKeysContent),
        HotkeyActionKind.Run => Plain(item.RunTarget),
        HotkeyActionKind.Window => item.WindowOp is { } op ? WindowOpLabel(op) : EmDash,
        HotkeyActionKind.Remap => item.RemapDest is { Length: > 0 } dest ? $"acts as {dest}" : EmDash,
        HotkeyActionKind.Disable => "does nothing",
        HotkeyActionKind.Raw => FirstLine(item.Body),
        _ => EmDash,
    };

    private const string EmDash = "—";

    private static string Plain(string? value) =>
        string.IsNullOrWhiteSpace(value) ? EmDash : value;

    // Multi-line payloads collapse to their first line with an ellipsis, so a grid row never
    // grows to the height of a whole replacement block.
    private static string FirstLine(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return EmDash;

        int newline = value.IndexOf('\n');
        if (newline < 0)
            return value.Trim();

        return $"{value[..newline].Trim()}…";
    }
}
```

- [ ] **Step 4: Implement the chip**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyActionChip.razor`:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Helpers
@using MudBlazor

@* Lives in its own component so the desktop grid and the mobile list cannot drift apart;
   the per-kind tints ride along in the scoped CSS. Raw carries its warning in aria-label
   because the chip's colour and icon alone are not exposed to screen readers. *@
<MudChip T="string" Size="Size.Small" Variant="Variant.Text"
         Class="@HotkeyActionDisplay.ChipClass(Kind)"
         Icon="@HotkeyActionDisplay.Icon(Kind)"
         UserAttributes="@ChipAttributes()">@HotkeyActionDisplay.Label(Kind)</MudChip>

@code {
    [Parameter, EditorRequired] public HotkeyActionKind Kind { get; set; }

    private Dictionary<string, object?> ChipAttributes() => Kind == HotkeyActionKind.Raw
        ? new Dictionary<string, object?>
        {
            ["aria-label"] = $"{HotkeyActionDisplay.Label(Kind)}. {HotkeyActionDisplay.RawWarningText}",
            ["data-test"] = "raw-action-chip",
        }
        : new Dictionary<string, object?> { ["data-test"] = "action-chip" };
}
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyActionChip.razor.css`:

```css
/* Per-kind tints. Kept deliberately low-saturation so seven chips in one column read as a
   set rather than a warning panel; Raw is the only one allowed to shout. OKLCH refinement
   of these values is Wave 4. */
.action-chip--sendtext { background: var(--mud-palette-action-default-hover); }
.action-chip--sendkeys { background: var(--mud-palette-info-hover); }
.action-chip--run { background: var(--mud-palette-success-hover); }
.action-chip--window { background: var(--mud-palette-primary-hover); }
.action-chip--remap { background: var(--mud-palette-secondary-hover); }
.action-chip--disable { background: var(--mud-palette-action-disabled-background); }
.action-chip--raw { background: var(--mud-palette-warning-hover); }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyActionDisplayTests"
```
Expected: PASS, 16 tests.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Helpers src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys tests/AHKFlowApp.UI.Blazor.Tests/Helpers
git commit -m "feat: add single-sourced hotkey action display + chip"
```

---

### Task 7: KeyPicker component

One role-parameterized picker, used three times in Wave 1 (hotkey `Key`, SendKeys token key, Remap destination) and a fourth time in Wave 2 (combo prefix). `MudAutocomplete` with `CoerceValue` so a typed `vk1B`/`sc001` passes straight through — the registry path and the escape hatch share one field, with no mode toggle.

> **`T` stays `string`, deliberately.** `MudAutocomplete` 9.3.0 has **no `GroupBy` parameter** — grouping is a `MudSelect` feature — so switching to `T="HotkeyKeyDto"` would buy nothing on that front, and it would actively break the escape hatch: `CoerceValue` sets `Value` from typed text, and there is no string→DTO conversion. Grouping is conveyed instead by ordering results by group (Task 4's `ForRoleAsync`) and rendering the group as dimmed secondary text per item via `ItemTemplate`, which is `RenderFragment<string>` here and looks the group up through `GroupOf`.

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Common/KeyPicker.razor`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/KeyPickerTests.cs`

**Interfaces:**
- Consumes: `IHotkeyKeyCatalog.ForRoleAsync` (Task 4).
- Produces: `<KeyPicker Role="HotkeyKey" Label="Key" @bind-Value="..." Error="..." ErrorText="..." DataTest="key-picker" />`.

- [ ] **Step 1: Write the failing test**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Components/KeyPickerTests.cs`:

```csharp
using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components;

public sealed class KeyPickerTests : TestContext
{
    private static readonly HotkeyKeyDto[] Keys =
    [
        new("F1", "Function keys", ["HotkeyKey", "RemapDest"], true),
        new("c", "Letters & digits", ["HotkeyKey", "SendToken"], false),
        new("Volume_Up", "Media & browser", ["SendToken"], true),
    ];

    private IHotkeyKeyCatalog SetupCatalog()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
        IHotkeyKeyCatalog catalog = Substitute.For<IHotkeyKeyCatalog>();
        // Mirrors the real ForRoleAsync: filter by role, then order by group so groups cluster.
        catalog.ForRoleAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult<IReadOnlyList<HotkeyKeyDto>>(
                [.. Keys.Where(k => k.Roles.Contains(call.Arg<string>()))
                        .OrderBy(k => k.Group, StringComparer.Ordinal)
                        .ThenBy(k => k.Canonical, StringComparer.OrdinalIgnoreCase)]));
        catalog.GroupOf(Arg.Any<string>())
            .Returns(call => Keys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.Group);
        Services.AddSingleton(catalog);
        return catalog;
    }

    [Fact]
    public async Task SearchAsync_ReturnsOnlyKeysForTheConfiguredRole()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderComponent<KeyPicker>(p => p
            .Add(x => x.Role, "SendToken")
            .Add(x => x.Label, "Send key"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("", CancellationToken.None);

        matches.Should().BeEquivalentTo(["c", "Volume_Up"]);
    }

    [Fact]
    public async Task SearchAsync_FiltersByTypedFragmentCaseInsensitively()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderComponent<KeyPicker>(p => p
            .Add(x => x.Role, "SendToken"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("vol", CancellationToken.None);

        matches.Should().ContainSingle().Which.Should().Be("Volume_Up");
    }

    [Fact]
    public async Task SearchAsync_TypedVirtualKeyCodeIsOfferedVerbatim()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderComponent<KeyPicker>(p => p
            .Add(x => x.Role, "HotkeyKey"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("vk1B", CancellationToken.None);

        matches.Should().Contain("vk1B");
    }

    [Fact]
    public void Renders_WithConfiguredLabelAndDataTest()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderComponent<KeyPicker>(p => p
            .Add(x => x.Role, "HotkeyKey")
            .Add(x => x.Label, "Key")
            .Add(x => x.DataTest, "key-picker"));

        cut.Markup.Should().Contain("key-picker");
    }

    [Fact]
    public async Task SearchAsync_PreservesTheCatalogsGroupOrdering()
    {
        // MudAutocomplete 9.3.0 cannot render group headers, so clustering depends entirely on
        // the order ForRoleAsync returns. Re-sorting here would scatter the groups.
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderComponent<KeyPicker>(p => p
            .Add(x => x.Role, "HotkeyKey"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("", CancellationToken.None);

        // Ordinal: "Function keys" < "Letters & digits", so F1 precedes c.
        matches.Should().ContainInOrder("F1", "c");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~KeyPickerTests"
```
Expected: FAIL — `KeyPicker` not defined.

- [ ] **Step 3: Verify the MudAutocomplete surface**

Before writing markup, confirm the parameter names against the pinned 9.3.0 docs:

```
mcp__mudblazor__get_component_parameters with componentName "MudAutocomplete"
```

Confirm `SearchFunc`, `CoerceValue`, `CoerceText`, `ResetValueOnEmptyText`, `MaxItems`, `ItemTemplate`, `Value`, `ValueChanged`, `Error`, `ErrorText` exist with those exact spellings. If any differ, use the documented name — do not use the spelling below on faith.

Two defaults matter and are overridden below: `MaxItems` defaults to **10**, which would silently truncate a ~100-key registry, so it is set to `null` (unlimited, scrolling within `MaxHeight` 300 px). `DebounceInterval` defaults to **100 ms** and is the autocomplete's own keystroke debounce — unrelated to, and additive with, the dialog's 400 ms preview debounce. The markup below omits `Immediate`: `SearchFunc` plus `DebounceInterval` already drive the dropdown on each keystroke, so it earns nothing here even where it is inherited from `MudBaseInput`.

- [ ] **Step 4: Implement the picker**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Common/KeyPicker.razor`:

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using MudBlazor

@* One picker for every key-shaped field. Role selects which registry entries are offered, so
   the same control serves the hotkey key, the SendKeys token key and the remap destination —
   each of which has its own AHK grammar server-side. CoerceValue keeps the vkNN / scNNN escape
   hatch in the same field: anything typed that is not in the list is passed through and judged
   by server validation, which is the authority. *@
<MudAutocomplete T="string" Label="@Label" Value="@Value" ValueChanged="OnValueChanged"
                 SearchFunc="SearchAsync" CoerceValue="true" ResetValueOnEmptyText="false"
                 MaxItems="null" Dense="@Dense"
                 Error="@Error" ErrorText="@ErrorText"
                 HelperText="@HelperText"
                 UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = DataTest })">
    <ItemTemplate>
        @* Results arrive ordered by group, so groups cluster; this label is what tells the
           user which cluster they are looking at, standing in for the group headers
           MudAutocomplete 9.3.0 does not support. Blank for vk/sc codes, which have no group. *@
        <MudStack Row="true" Justify="Justify.SpaceBetween" AlignItems="AlignItems.Center" Class="flex-grow-1">
            <span>@context</span>
            @if (Catalog.GroupOf(context) is { } group)
            {
                <MudText Typo="Typo.caption" Color="Color.Tertiary">@group</MudText>
            }
        </MudStack>
    </ItemTemplate>
</MudAutocomplete>

@code {
    [Inject] private IHotkeyKeyCatalog Catalog { get; set; } = default!;

    /// <summary>Registry role whose keys this picker offers: HotkeyKey, ComboPrefix, SendToken, RemapSource or RemapDest.</summary>
    [Parameter, EditorRequired] public string Role { get; set; } = "HotkeyKey";

    [Parameter] public string? Label { get; set; }
    [Parameter] public string? Value { get; set; }
    [Parameter] public EventCallback<string?> ValueChanged { get; set; }
    [Parameter] public bool Error { get; set; }
    [Parameter] public string? ErrorText { get; set; }
    [Parameter] public string? HelperText { get; set; }
    [Parameter] public bool Dense { get; set; }
    [Parameter] public string DataTest { get; set; } = "key-picker";

    private Task OnValueChanged(string? value) => ValueChanged.InvokeAsync(value);

    /// <summary>
    /// Registry entries for this role matching the typed fragment, plus the fragment itself when
    /// it looks like a vk/sc code so the escape hatch is selectable rather than only typeable.
    /// Catalog order (group, then name) is preserved — re-sorting here would scatter the groups.
    /// </summary>
    internal async Task<IEnumerable<string>> SearchAsync(string? fragment, CancellationToken ct)
    {
        IReadOnlyList<HotkeyKeyDto> keys = await Catalog.ForRoleAsync(Role, ct);

        IEnumerable<string> matches = string.IsNullOrWhiteSpace(fragment)
            ? keys.Select(k => k.Canonical)
            : keys.Where(k => k.Canonical.Contains(fragment, StringComparison.OrdinalIgnoreCase))
                  .Select(k => k.Canonical);

        if (!string.IsNullOrWhiteSpace(fragment)
            && (fragment.StartsWith("vk", StringComparison.OrdinalIgnoreCase)
                || fragment.StartsWith("sc", StringComparison.OrdinalIgnoreCase))
            && !matches.Contains(fragment, StringComparer.OrdinalIgnoreCase))
        {
            matches = matches.Prepend(fragment);
        }

        return matches;
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~KeyPickerTests"
```
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Common tests/AHKFlowApp.UI.Blazor.Tests/Components
git commit -m "feat: add role-parameterized key picker"
```

---

### Task 8: Dialog rebuild

The centrepiece: seven action panels behind a wrapping toggle group, a live preview panel, and field-mapped server errors. The dialog goes from 133 lines to roughly 500.

Two structural notes:

- **Field errors use a dictionary**, not `HotstringEditDialog`'s 4-tuple. Seven panels have too many fields for positional returns; the key is the DTO field name, which is exactly what the server's `ProblemDetails` reports.
- **The preview panel is a direct port** of the hotstring one (`HotstringEditDialog.razor:219-256` markup, `:831-898` scheduling). Copy the generation-counter pattern verbatim — bumping a generation, not just cancelling, is what discards in-flight responses whose transport ignores cancellation.

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor.css`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Components/HotkeyEditDialogTests.cs`

**Interfaces:**
- Consumes: `HotkeyEditModel` (Task 5), `HotkeyActionDisplay` (Task 6), `KeyPicker` (Task 7), `IHotkeysApiClient.PreviewAsync` (Task 3), `EntityMultiSelect`.
- Produces: `HotkeyEditDialog` with `internal TimeSpan PreviewDebounce` (test seam, default 400 ms).

- [ ] **Step 1: Write the failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Components/HotkeyEditDialogTests.cs`. Model the fixture on the existing hotstring dialog tests inside `HotstringsPageTests.cs` — reuse its dialog-hosting helper rather than inventing a new one.

```csharp
using AHKFlowApp.UI.Blazor.Components.Hotkeys;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components;

public sealed class HotkeyEditDialogTests : TestContext
{
    [Fact]
    public void ActionSelector_OffersAllSevenKinds()
    {
        IRenderedComponent<HotkeyEditDialog> cut = RenderDialog(new HotkeyEditModel());

        foreach (HotkeyActionKind kind in Enum.GetValues<HotkeyActionKind>())
            cut.Markup.Should().Contain(HotkeyActionDisplayLabel(kind));
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, "sendtext-panel")]
    [InlineData(HotkeyActionKind.SendKeys, "sendkeys-panel")]
    [InlineData(HotkeyActionKind.Run, "run-panel")]
    [InlineData(HotkeyActionKind.Window, "window-panel")]
    [InlineData(HotkeyActionKind.Remap, "remap-panel")]
    [InlineData(HotkeyActionKind.Raw, "raw-panel")]
    public void SelectedKind_RevealsOnlyItsOwnPanel(HotkeyActionKind kind, string panelTest)
    {
        IRenderedComponent<HotkeyEditDialog> cut = RenderDialog(new HotkeyEditModel { ActionKind = kind });

        cut.FindAll($"[data-test={panelTest}]").Should().ContainSingle();
        cut.FindAll("[data-test$=-panel]").Should().ContainSingle();
    }

    [Fact]
    public void DisableKind_ShowsNoActionPanel()
    {
        IRenderedComponent<HotkeyEditDialog> cut =
            RenderDialog(new HotkeyEditModel { ActionKind = HotkeyActionKind.Disable });

        cut.FindAll("[data-test$=-panel]").Should().BeEmpty();
    }

    [Fact]
    public void RawKind_ShowsTheUncheckedScriptWarning()
    {
        IRenderedComponent<HotkeyEditDialog> cut =
            RenderDialog(new HotkeyEditModel { ActionKind = HotkeyActionKind.Raw });

        cut.Find("[data-test=raw-warning]").TextContent
            .Should().Contain("stop the whole profile script from loading");
    }

    [Fact]
    public void SwitchingKind_KeepsTheOutgoingKindsTypedValue()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Run, RunTarget = "notepad" };
        IRenderedComponent<HotkeyEditDialog> cut = RenderDialog(model);

        cut.Find("[data-test=action-kind-SendText]").Click();

        model.RunTarget.Should().Be("notepad");
        model.ActionKind.Should().Be(HotkeyActionKind.SendText);
    }

    [Fact]
    public void ValidationError_FromSave_LandsOnItsNamedField()
    {
        // Arrange a save returning 400 with { "Input.RunTarget": ["Run target is required."] },
        // then assert the run-target field renders that message rather than the generic alert.
    }
}
```

> The last test is a stub on purpose only in this listing — **write its body before implementing**, following `HotstringsPageTests`' existing 400-response arrangement. A test with no assertions is a plan failure; do not leave it empty in the committed file.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyEditDialogTests"
```
Expected: FAIL — panels and `data-test` hooks do not exist.

- [ ] **Step 3: Write the dialog markup**

Replace the `DialogContent` of `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor`. `TitleContent` (back button, title, Save) is unchanged from today.

```razor
    <DialogContent>
        <MudForm @ref="_form">
        <MudStack Spacing="3" Class="pa-2">

            @* ---- Activating input: key + modifiers ---- *@
            <KeyPicker Role="HotkeyKey" Label="Key" @bind-Value="Item.Key"
                       Error="@(FieldError(nameof(HotkeyEditModel.Key)) is not null)"
                       ErrorText="@FieldError(nameof(HotkeyEditModel.Key))"
                       HelperText="Pick a key, or type a vk/sc code such as vk1B."
                       DataTest="key-picker" />
            <MudStack Row="true" Spacing="2">
                <MudCheckBox T="bool" Value="Item.Ctrl" ValueChanged="@(async (bool v) => { Item.Ctrl = v; await RefreshPreviewAsync(debounce: false); })" Label="Ctrl"
                             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "ctrl-checkbox" })" />
                <MudCheckBox T="bool" Value="Item.Alt" ValueChanged="@(async (bool v) => { Item.Alt = v; await RefreshPreviewAsync(debounce: false); })" Label="Alt"
                             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "alt-checkbox" })" />
                <MudCheckBox T="bool" Value="Item.Shift" ValueChanged="@(async (bool v) => { Item.Shift = v; await RefreshPreviewAsync(debounce: false); })" Label="Shift"
                             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "shift-checkbox" })" />
                <MudCheckBox T="bool" Value="Item.Win" ValueChanged="@(async (bool v) => { Item.Win = v; await RefreshPreviewAsync(debounce: false); })" Label="Win"
                             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "win-checkbox" })" />
            </MudStack>

            @* ---- Action selector. Generated from the enum so the set cannot drift. ---- *@
            <MudToggleGroup T="HotkeyActionKind" Class="action-kind-group"
                            Value="Item.ActionKind" ValueChanged="OnActionKindChangedAsync"
                            UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "action-kind-selector" })">
                @foreach (HotkeyActionKind kind in Enum.GetValues<HotkeyActionKind>())
                {
                    <MudToggleItem Value="@kind"
                                   UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = $"action-kind-{kind}" })">
                        <MudStack Row="true" Spacing="1" AlignItems="AlignItems.Center">
                            <MudIcon Icon="@HotkeyActionDisplay.Icon(kind)" Size="Size.Small" />
                            <MudText>@HotkeyActionDisplay.Label(kind)</MudText>
                        </MudStack>
                    </MudToggleItem>
                }
            </MudToggleGroup>

            @* ---- Exactly one action panel. Disable renders none: it owns no fields, and an
                   empty bordered box reads as a bug rather than as "nothing to configure". ---- *@
            @switch (Item.ActionKind)
            {
                case HotkeyActionKind.SendText:
                    <div data-test="sendtext-panel">
                        <MudTextField T="string" Label="Text to type" @bind-Value="Item.Text"
                                      Lines="4" MaxLength="@HotkeyEditModel.TextMaxLength" Immediate="true"
                                      OnDebounceIntervalElapsed="@(() => RefreshPreviewAsync(debounce: false))"
                                      DebounceInterval="300"
                                      Error="@(FieldError(nameof(HotkeyEditModel.Text)) is not null)"
                                      ErrorText="@FieldError(nameof(HotkeyEditModel.Text))"
                                      HelperText="Typed literally. Quotes and newlines are escaped for you."
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "text-input" })" />
                    </div>
                    break;

                case HotkeyActionKind.SendKeys:
                    <div data-test="sendkeys-panel">
                        <MudStack Row="true" Spacing="2">
                            <MudCheckBox T="bool" Value="_sendCtrl" ValueChanged="@(async (bool v) => { _sendCtrl = v; await ComposeSendKeysAsync(); })" Label="Ctrl"
                                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "send-ctrl-checkbox" })" />
                            <MudCheckBox T="bool" Value="_sendAlt" ValueChanged="@(async (bool v) => { _sendAlt = v; await ComposeSendKeysAsync(); })" Label="Alt"
                                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "send-alt-checkbox" })" />
                            <MudCheckBox T="bool" Value="_sendShift" ValueChanged="@(async (bool v) => { _sendShift = v; await ComposeSendKeysAsync(); })" Label="Shift"
                                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "send-shift-checkbox" })" />
                            <MudCheckBox T="bool" Value="_sendWin" ValueChanged="@(async (bool v) => { _sendWin = v; await ComposeSendKeysAsync(); })" Label="Win"
                                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "send-win-checkbox" })" />
                        </MudStack>
                        <KeyPicker Role="SendToken" Label="Key to press"
                                   Value="_sendKey" ValueChanged="OnSendKeyChangedAsync"
                                   Error="@(FieldError(nameof(HotkeyEditModel.SendKeysContent)) is not null)"
                                   ErrorText="@FieldError(nameof(HotkeyEditModel.SendKeysContent))"
                                   DataTest="send-key-picker" />
                    </div>
                    break;

                case HotkeyActionKind.Run:
                    <div data-test="run-panel">
                        <MudSelect T="RunTargetKind?" Label="Target type" Value="Item.RunTargetKind"
                                   ValueChanged="OnRunTargetKindChangedAsync"
                                   Error="@(FieldError(nameof(HotkeyEditModel.RunTargetKind)) is not null)"
                                   ErrorText="@FieldError(nameof(HotkeyEditModel.RunTargetKind))"
                                   UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "run-target-kind-select" })">
                            @foreach (RunTargetKind kind in Enum.GetValues<RunTargetKind>())
                            {
                                <MudSelectItem T="RunTargetKind?" Value="@kind">@HotkeyActionDisplay.RunTargetKindLabel(kind)</MudSelectItem>
                            }
                        </MudSelect>
                        <MudTextField T="string" Label="Target" @bind-Value="Item.RunTarget"
                                      MaxLength="@HotkeyEditModel.RunTargetMaxLength" Immediate="true"
                                      OnDebounceIntervalElapsed="@(() => RefreshPreviewAsync(debounce: false))"
                                      DebounceInterval="300"
                                      Placeholder="@RunTargetPlaceholder()"
                                      Error="@(FieldError(nameof(HotkeyEditModel.RunTarget)) is not null)"
                                      ErrorText="@FieldError(nameof(HotkeyEditModel.RunTarget))"
                                      HelperText="A command line — arguments are allowed, e.g. rundll32.exe user32.dll,LockWorkStation"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "run-target-input" })" />
                    </div>
                    break;

                case HotkeyActionKind.Window:
                    <div data-test="window-panel">
                        <MudSelect T="WindowOp?" Label="Do what" Value="Item.WindowOp"
                                   ValueChanged="OnWindowOpChangedAsync"
                                   Error="@(FieldError(nameof(HotkeyEditModel.WindowOp)) is not null)"
                                   ErrorText="@FieldError(nameof(HotkeyEditModel.WindowOp))"
                                   HelperText="Applies to the active window."
                                   UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "window-op-select" })">
                            @foreach (WindowOp op in Enum.GetValues<WindowOp>())
                            {
                                <MudSelectItem T="WindowOp?" Value="@op">@HotkeyActionDisplay.WindowOpLabel(op)</MudSelectItem>
                            }
                        </MudSelect>
                    </div>
                    break;

                case HotkeyActionKind.Remap:
                    <div data-test="remap-panel">
                        <KeyPicker Role="RemapDest" Label="Behaves as"
                                   Value="Item.RemapDest" ValueChanged="OnRemapDestChangedAsync"
                                   Error="@(FieldError(nameof(HotkeyEditModel.RemapDest)) is not null)"
                                   ErrorText="@FieldError(nameof(HotkeyEditModel.RemapDest))"
                                   HelperText="The key this one will act as."
                                   DataTest="remap-dest-picker" />
                    </div>
                    break;

                case HotkeyActionKind.Raw:
                    <div data-test="raw-panel">
                        <MudAlert Severity="Severity.Warning" Dense="true" Class="mb-2"
                                  UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "raw-warning" })">
                            @HotkeyActionDisplay.RawWarningText
                        </MudAlert>
                        <MudTextField T="string" Label="Action body" @bind-Value="Item.Body"
                                      Lines="6" Class="raw-body" MaxLength="@HotkeyEditModel.BodyMaxLength" Immediate="true"
                                      OnDebounceIntervalElapsed="@(() => RefreshPreviewAsync(debounce: false))"
                                      DebounceInterval="300"
                                      Error="@(FieldError(nameof(HotkeyEditModel.Body)) is not null)"
                                      ErrorText="@FieldError(nameof(HotkeyEditModel.Body))"
                                      HelperText="Emitted verbatim inside { }. Braces must balance; # directives are rejected."
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "raw-body-input" })" />
                    </div>
                    break;
            }

            @* ---- Generated code preview. Ported from HotstringEditDialog; no delivery chip,
                   because hotkeys have no delivery choice. ---- *@
            <MudExpansionPanels UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "ahk-preview" })">
                <MudExpansionPanel Text="Generated AutoHotkey code" Expanded="_previewExpanded"
                                   ExpandedChanged="OnPreviewExpandedChangedAsync">
                    @if (_previewPending)
                    {
                        <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="2" Class="mb-1"
                                  UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "preview-pending" })">
                            <MudProgressCircular Size="Size.Small" Indeterminate="true" />
                            <MudText Typo="Typo.caption">Updating preview…</MudText>
                        </MudStack>
                    }
                    @if (_previewError is not null)
                    {
                        <MudText Color="Color.Error" Class="@(_previewPending ? "preview-stale" : null)"
                                 UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "preview-error" })">
                            @_previewError
                        </MudText>
                    }
                    else if (_previewSnippet is not null)
                    {
                        <div class="preview-snippet-container">
                            <MudIconButton Icon="@Icons.Material.Filled.ContentCopy" Size="Size.Small"
                                           Class="preview-copy" Disabled="@_previewPending"
                                           OnClick="CopyPreviewAsync"
                                           UserAttributes="@(new Dictionary<string, object?> { ["aria-label"] = "Copy generated AutoHotkey code", ["data-test"] = "preview-copy" })" />
                            <pre class="@($"preview-snippet{(_previewPending ? " preview-stale" : "")}")"
                                 data-test="preview-snippet">@_previewSnippet</pre>
                        </div>
                    }
                </MudExpansionPanel>
            </MudExpansionPanels>

            @* ---- Metadata: unchanged from today's dialog ---- *@
            <MudTextField T="string" Label="Description" @bind-Value="Item.Description"
                          Required="true" RequiredError="Description is required" MaxLength="200"
                          Error="@(FieldError(nameof(HotkeyEditModel.Description)) is not null)"
                          ErrorText="@FieldError(nameof(HotkeyEditModel.Description))"
                          HelperText="Emitted as ; comment lines in the generated script."
                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "description-input" })" />

            <MudCheckBox T="bool" @bind-Value="Item.AppliesToAllProfiles" Label="Apply to all profiles"
                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "applies-to-all-checkbox" })" />
            @if (!Item.AppliesToAllProfiles)
            {
                <EntityMultiSelect Options="_profileOptions" Label="Profiles"
                                   SelectedIds="Item.ProfileIds"
                                   SelectedIdsChanged="ids => Item.ProfileIds = [.. ids]"
                                   DataTest="profile-select" />
            }

            <EntityMultiSelect Options="_categoryOptions" Label="Categories"
                               SelectedIds="Item.CategoryIds"
                               SelectedIdsChanged="ids => Item.CategoryIds = [.. ids]"
                               DataTest="category-select" />

            @if (_error is not null)
            {
                <MudAlert Severity="Severity.Error">@_error</MudAlert>
            }
        </MudStack>
        </MudForm>
    </DialogContent>
```

Add the matching `@using` lines at the top of the file: `AHKFlowApp.UI.Blazor.Components.Common` (for `KeyPicker`) and `AHKFlowApp.UI.Blazor.Helpers` (for `HotkeyActionDisplay`).

`RunTargetPlaceholder()` is a one-liner in the code block — the field's placeholder is the only thing `RunTargetKind` changes in the UI, since all three kinds emit the same `Run("<escaped>")`:

```csharp
    private string RunTargetPlaceholder() => Item.RunTargetKind switch
    {
        DTOs.RunTargetKind.Url => "https://github.com",
        DTOs.RunTargetKind.Folder => @"C:\Users\me\Documents",
        _ => "notepad.exe",
    };
```

- [ ] **Step 4: Write the dialog code block**

Port the preview machinery from `HotstringEditDialog` and add the two hotkey-specific pieces:

```csharp
    // Test seam: bUnit drives the debounce to zero so preview assertions do not sleep.
    internal TimeSpan PreviewDebounce { get; set; } = TimeSpan.FromMilliseconds(400);

    private readonly Dictionary<string, string> _fieldErrors = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Server-reported error for a DTO field name, or null. Drives every field's Error/ErrorText.</summary>
    private string? FieldError(string field) =>
        _fieldErrors.TryGetValue(field, out string? message) ? message : null;

    /// <summary>
    /// Maps a ProblemDetails validation dictionary onto field names. Property paths arrive as
    /// e.g. "Input.RunTarget" — the last dotted part is the field. Anything that maps to no
    /// known field falls through to the generic alert rather than being silently dropped.
    /// </summary>
    private string? ApplyFieldErrors(IReadOnlyDictionary<string, string[]> errors)
    {
        _fieldErrors.Clear();
        List<string> unmapped = [];

        foreach ((string key, string[] messages) in errors)
        {
            if (messages.FirstOrDefault() is not { } message)
                continue;

            string field = key[(key.LastIndexOf('.') + 1)..];
            if (KnownFields.Contains(field))
                _fieldErrors.TryAdd(field, message);
            else
                unmapped.Add(message);
        }

        return unmapped.FirstOrDefault();
    }

    private static readonly HashSet<string> KnownFields = new(StringComparer.OrdinalIgnoreCase)
    {
        nameof(HotkeyEditModel.Key),
        nameof(HotkeyEditModel.Description),
        nameof(HotkeyEditModel.Text),
        nameof(HotkeyEditModel.SendKeysContent),
        nameof(HotkeyEditModel.RunTarget),
        nameof(HotkeyEditModel.RunTargetKind),
        nameof(HotkeyEditModel.WindowOp),
        nameof(HotkeyEditModel.RemapDest),
        nameof(HotkeyEditModel.Body),
    };

    /// <summary>
    /// Switching kind drops the outgoing kind's field errors (a stale Raw brace message must not
    /// linger on the incoming kind's fields) and re-previews. Field values are deliberately kept:
    /// gating to the active kind happens on the wire, so toggling away and back loses nothing.
    /// </summary>
    private async Task OnActionKindChangedAsync(HotkeyActionKind kind)
    {
        if (kind == Item.ActionKind)
            return;

        Item.ActionKind = kind;
        _fieldErrors.Clear();
        await RefreshPreviewAsync(debounce: false);
    }
```

Then copy, renamed for hotkeys, from `HotstringEditDialog.razor`: `SchedulePreview` (`:831`), `CancelPendingPreview` (`:849`), `RunPreviewAsync` (`:860`), and `Dispose` (`:969`). `RunPreviewAsync` calls `Api.PreviewAsync(Item.ToPreviewRequest(), ct)`; on `ApiResultStatus.Validation` it calls `ApplyFieldErrors` and puts the returned unmapped message in `_previewError`.

`SaveAsync` keeps today's shape, with the error branch replaced:

```csharp
            if (!result.IsSuccess)
            {
                if (result.Status == ApiResultStatus.Conflict)
                    _fieldErrors[nameof(HotkeyEditModel.Key)] = ApiErrorMessageFactory.Build(result.Status, result.Problem);
                else if (result.Status == ApiResultStatus.Validation && result.Problem?.Errors is { Count: > 0 } errors)
                    _error = ApplyFieldErrors(errors);
                else
                    _error = ApiErrorMessageFactory.Build(result.Status, result.Problem);

                return;
            }
```

**Per-panel change handlers.** Each writes its field then re-previews immediately (no debounce — these are discrete choices, not typing):

```csharp
    private async Task OnRunTargetKindChangedAsync(RunTargetKind? kind)
    {
        Item.RunTargetKind = kind;
        await RefreshPreviewAsync(debounce: false);
    }

    private async Task OnWindowOpChangedAsync(WindowOp? op)
    {
        Item.WindowOp = op;
        await RefreshPreviewAsync(debounce: false);
    }

    private async Task OnRemapDestChangedAsync(string? dest)
    {
        // A remap destination is never braced and never carries modifiers (backend Task 3
        // rejects {Ctrl} and ^a), so it is persisted exactly as the picker yields it.
        Item.RemapDest = dest;
        await RefreshPreviewAsync(debounce: false);
    }

    private async Task RefreshPreviewAsync(bool debounce)
    {
        if (!_previewExpanded)
            return;

        SchedulePreview(Item.ToPreviewRequest(), debounce);
        await Task.CompletedTask;
    }

    private async Task OnPreviewExpandedChangedAsync(bool expanded)
    {
        _previewExpanded = expanded;
        if (expanded)
            await RefreshPreviewAsync(debounce: false);
        else
            CancelPendingPreview();
    }
```

**SendKeys token composition.** The panel edits modifier checkboxes and a key, but persists one token string:

```csharp
    private bool _sendCtrl, _sendAlt, _sendShift, _sendWin;
    private string? _sendKey;

    private async Task OnSendKeyChangedAsync(string? key)
    {
        _sendKey = key;
        await ComposeSendKeysAsync();
    }

    /// <summary>
    /// Composes the discrete picker state into the single canonical token the server validates:
    /// optional ^!+# modifiers then exactly one key. Bracing comes from the registry's
    /// RequiresBracesInSend, which is true for named entries ({Volume_Up}) and for vk/sc codes
    /// ({vk1B}), false for a single printable character (c). Note '*' is not a Send modifier
    /// and is deliberately absent.
    /// </summary>
    private async Task ComposeSendKeysAsync()
    {
        string mods = $"{(_sendCtrl ? "^" : "")}{(_sendAlt ? "!" : "")}{(_sendShift ? "+" : "")}{(_sendWin ? "#" : "")}";

        if (string.IsNullOrEmpty(_sendKey))
        {
            Item.SendKeysContent = null;
        }
        else
        {
            string key = Catalog.RequiresBracesInSend(_sendKey) ? $"{{{_sendKey}}}" : _sendKey;
            Item.SendKeysContent = $"{mods}{key}";
        }

        await RefreshPreviewAsync(debounce: false);
    }

    /// <summary>
    /// Splits a stored token back into the checkboxes and key so reopening an existing SendKeys
    /// row shows the state that produced it. Leading ^!+# are modifiers; the remainder is the
    /// key, unwrapped if braced.
    /// </summary>
    private void DecomposeSendKeys()
    {
        _sendCtrl = _sendAlt = _sendShift = _sendWin = false;
        _sendKey = null;

        if (Item.SendKeysContent is not { Length: > 0 } token)
            return;

        int i = 0;
        for (; i < token.Length; i++)
        {
            switch (token[i])
            {
                case '^': _sendCtrl = true; continue;
                case '!': _sendAlt = true; continue;
                case '+': _sendShift = true; continue;
                case '#': _sendWin = true; continue;
            }
            break;
        }

        string rest = token[i..];
        _sendKey = rest.StartsWith('{') && rest.EndsWith('}') ? rest[1..^1] : rest;
    }
```

Call `DecomposeSendKeys()` from `OnParametersSet` whenever the incoming `Item` changes and its kind is `SendKeys`, alongside the existing profile/category option projection. Inject the catalog into the dialog for `RequiresBracesInSend`:

```csharp
    [Inject] private IHotkeyKeyCatalog Catalog { get; set; } = default!;
```

- [ ] **Step 5: Add the scoped CSS**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyEditDialog.razor.css`:

```css
/* MudToggleGroup has no wrap parameter in 9.3.0 and its Vertical switch is a C# parameter, so
   a CSS-only breakpoint cannot flip it. Forcing wrap here keeps all seven kinds visible and
   equal at every width, with no breakpoint service and no JS. */
.action-kind-group ::deep .mud-toggle-group {
    flex-wrap: wrap;
}

.raw-body ::deep textarea {
    font-family: var(--mud-typography-caption-family, monospace);
    font-size: 0.85rem;
}

/* Preview panel — copied from HotstringEditDialog.razor.css so the two dialogs render the
   generated-code block identically. */
.preview-snippet-container {
    position: relative;
    max-width: 100%;
}

.preview-snippet {
    margin: 0;
    padding: 8px 40px 8px 12px;
    font-size: 0.85rem;
    background: var(--mud-palette-background-grey);
    border-radius: 4px;
    overflow-x: auto;
    max-width: 100%;
}

.preview-snippet-container ::deep .preview-copy {
    position: absolute;
    top: 2px;
    right: 2px;
}

.preview-stale {
    opacity: 0.5;
}
```

Add `Class="action-kind-group"` to the `MudToggleGroup` so the wrap rule matches.

- [ ] **Step 6: Run tests to verify they pass**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeyEditDialogTests"
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys tests/AHKFlowApp.UI.Blazor.Tests/Components
git commit -m "feat: rebuild hotkey dialog with seven action panels + preview"
```

---

### Task 9: Grid collapse and mobile list

Collapses the desktop grid from 11 columns to 6 and moves both branches onto `HotkeyActionDisplay`. This is the task that makes the page compile again.

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs`

**Interfaces:**
- Consumes: `HotkeyActionDisplay`, `HotkeyActionChip` (Task 6), `KeyPicker` (Task 7), `IHotkeyKeyCatalog` (Task 4), `HotkeyEditModel.IsInlineEditable` (Task 5).
- Produces: no new public surface.

- [ ] **Step 1: Write the failing tests**

Add to `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotkeysPageTests.cs`:

```csharp
    [Fact]
    public void Grid_RendersSixColumnsPlusSelectAndActions()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        IReadOnlyList<string> headers = [.. cut.FindAll("th").Select(th => th.TextContent.Trim())];

        headers.Should().Contain(["Description", "Hotkey", "Action", "Profiles", "Categories"]);
        headers.Should().NotContain(["Ctrl", "Alt", "Shift", "Win", "Key", "Parameters"]);
    }

    [Fact]
    public void Grid_ActionCellShowsChipAndSummary()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.Find("[data-test=action-chip]").TextContent.Should().Contain("Run");
        cut.Markup.Should().Contain("notepad");
    }

    [Fact]
    public void Grid_HotkeyCellShowsComboLabel()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.Markup.Should().Contain("Win+N");
    }

    [Fact]
    public void EditButton_OnRawRow_OpensDialogInsteadOfInlineEdit()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneHotkeyOfKind(HotkeyActionKind.Raw));

        cut.Find(".start-edit").Click();

        cut.FindAll("[data-test=raw-body-input]").Should().NotBeEmpty();   // dialog opened
        cut.FindAll(".commit-edit").Should().BeEmpty();                    // no inline row
    }

    [Fact]
    public void EditButton_OnRunRow_StartsInlineEdit()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.Find(".start-edit").Click();

        cut.FindAll(".commit-edit").Should().ContainSingle();
    }

    [Fact]
    public void EditButton_OnRunRowWithLegacyInvalidKey_OpensDialog()
    {
        // Catalog reports the key invalid -> the row is not inline-editable even though its
        // kind is Run, which is how un-migratable legacy rows surface with no extra UI.
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey(key: "!!legacy!!"), keysValid: false);

        cut.Find(".start-edit").Click();

        cut.FindAll(".commit-edit").Should().BeEmpty();
    }
```

> Build `RenderPageWith`, `OneRunHotkey`, `OneHotkeyOfKind` on top of the fixture helpers already in this file; register a stubbed `IHotkeyKeyCatalog` whose `IsValidKey` returns the `keysValid` argument.
>
> **Selectors follow the page's existing convention** (Global Constraints): buttons are CSS classes — `.add-hotkey`, `.start-edit`, `.commit-edit`, `.cancel-edit`, `.show-history`, `.delete` — and only inputs carry `data-test`. `.commit-edit` renders only while a row is in inline-edit mode, which makes it the honest probe for "did this row go inline or open the dialog". Do not add `data-test` hooks to these buttons.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotkeysPageTests"
```
Expected: FAIL to compile — the page still binds `x.Action` and `x.Parameters`.

- [ ] **Step 3: Rewrite the grid columns**

In `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor`, replace the ten `<PropertyColumn>`/`<TemplateColumn>` entries between `<SelectColumn>` and the trailing "Actions" column with five:

- `<PropertyColumn Property="x => x.Description" Title="Description">` — unchanged in both display and edit mode; its editor already carries `data-test="description-input"`.
- `<TemplateColumn Title="Hotkey" Sortable="false">` — display mode renders `<code>@HotkeyActionDisplay.ComboLabel(context.Item)</code>`; edit mode renders `<KeyPicker Role="HotkeyKey" Dense="true" @bind-Value="context.Item.Key" ... />` plus the four dense modifier checkboxes, and shows the conflict message from the page's existing key-error state.
- `<TemplateColumn Title="Action" Sortable="false">` — display mode renders `<HotkeyActionChip Kind="context.Item.ActionKind" />` followed by `@HotkeyActionDisplay.Summary(context.Item)`; edit mode renders a single `MudTextField` bound to `Item.Text` or `Item.RunTarget` per kind. The chip stays visible in edit mode — the kind is not inline-changeable, so it is context, not a control.
- Profiles and Categories columns — unchanged.

Sorting: `Key` remains a valid server sort field, so set `SortBy="x => x.Key"` on the Hotkey column. `ActionKind` is the new sort field for the Action column. Do **not** offer sorting on the summary text — no server field backs it.

- [ ] **Step 4: Route the edit button by capability, and send Add to the dialog**

`StartEditAsync` (currently at `Hotkeys.razor:492`) becomes async and inspects the row:

```csharp
    [Inject] private IHotkeyKeyCatalog KeyCatalog { get; set; } = default!;

    // One button, two destinations: rows whose whole payload is a single text field edit in
    // place; everything else — and any row whose key would fail server validation — opens the
    // dialog, where the fields exist and the validation error already shows on open.
    private async Task StartEditAsync(HotkeyEditModel item)
    {
        if (item.IsInlineEditable(KeyCatalog))
            _editingItem = item;
        else
            await OpenEditDialogAsync(item);
    }
```

`RenderActions`' edit button already calls `StartEditAsync(item)`; the call site needs no change beyond awaiting.

**`StartAddAsync` must now open the dialog.** Today it creates an inline `_pendingCreate` row (`Hotkeys.razor:482`). A new hotkey has to choose an `ActionKind`, and kind is deliberately not inline-changeable — an inline create row could only ever produce the default kind. Replace it:

```csharp
    // A new hotkey must pick its action kind, which the grid cannot express, so Add always
    // opens the dialog. _pendingCreate and the inline-create path retire with it.
    private Task StartAddAsync() => OpenEditDialogAsync(new HotkeyEditModel());
```

Then delete the now-unreachable `_pendingCreate` field and every branch that tests it — the `Disabled` binding on the Add button (`Hotkeys.razor:19`), the visibility switch in `LoadServerData` (~`:374-389`), and `_commitAttempted` if nothing else reads it. Confirm `OpenEditDialogAsync` handles a model with `Id is null` by calling `CreateAsync`; it already routes on `Id` today.

Ensure the catalog is warmed on page load so `IsValidKey` is not answering optimistically for the first render:

```csharp
    protected override async Task OnInitializedAsync()
    {
        // …existing profile/category loads…
        await KeyCatalog.ForRoleAsync("HotkeyKey", _cts.Token);
    }
```

- [ ] **Step 5: Move the mobile list onto the shared helper**

In `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyMobileList.razor`:
- Delete the local `FormatCombo` method and replace its call site at line 44 with `@HotkeyActionDisplay.ComboLabel(item)`.
- In the expanded row, replace `<strong>Action:</strong> @item.Action` with `<HotkeyActionChip Kind="item.ActionKind" />` plus `@HotkeyActionDisplay.Summary(item)`.
- Delete the `Parameters` block (lines 54-57) — the summary now carries it.

- [ ] **Step 6: Run the full frontend suite**

```bash
dotnet test tests/AHKFlowApp.UI.Blazor.Tests
```
Expected: PASS. This is the first green build of the frontend since Task 2.

- [ ] **Step 7: Format and commit**

```bash
dotnet format AHKFlowApp.slnx
git add src/Frontend/AHKFlowApp.UI.Blazor tests/AHKFlowApp.UI.Blazor.Tests
git commit -m "feat: collapse hotkey grid to six columns, route edit by capability"
```

---

### Task 10: End-to-end flow and verification

One browser flow proving dialog → API → preview → grid, plus the mobile-list update and the full-suite gate.

**Files:**
- Create: `tests/AHKFlowApp.E2E.Tests/HotkeysCrudFlowTests.cs`
- Modify: `tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs`

**Interfaces:**
- Consumes: the running worktree stack — **UI 5605 / API 5604** for this worktree (`hotkey-ui-plan`). Read `launchSettings.json` to confirm before running; the numbers differ per worktree and the backend plan's 5602/5603 belong to `hotkey-redesign`.

- [ ] **Step 1: Write the E2E flow**

Create `tests/AHKFlowApp.E2E.Tests/HotkeysCrudFlowTests.cs`, modelled on `HotstringsCrudFlowTests.cs`:

```csharp
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection("E2E")]
public sealed class HotkeysCrudFlowTests(E2EFixture fixture)
{
    [Fact]
    public async Task CreateRunHotkey_ShowsPreviewThenAppearsInGridWithActionChip()
    {
        IPage page = await fixture.NewPageAsync();
        await page.GotoAsync($"{fixture.BaseUrl}/hotkeys");

        await page.ClickAsync(".add-hotkey");
        await page.FillAsync("[data-test=description-input] input", "E2E open notepad");
        await page.FillAsync("[data-test=key-picker] input", "n");
        await page.ClickAsync("[data-test=win-checkbox] input");
        await page.ClickAsync("[data-test=action-kind-Run]");
        await page.FillAsync("[data-test=run-target-input] input", "notepad");

        await page.ClickAsync("[data-test=ahk-preview]");
        await page.WaitForSelectorAsync("[data-test=preview-snippet]");
        string snippet = await page.InnerTextAsync("[data-test=preview-snippet]");
        snippet.Should().Contain("#n::Run(\"notepad\")");

        await page.ClickAsync(".commit-edit");

        await page.WaitForSelectorAsync("text=E2E open notepad");
        (await page.InnerTextAsync("[data-test=action-chip]")).Should().Contain("Run");
        (await page.TextContentAsync("body"))!.Should().Contain("Win+N");
    }
}
```

> Copy the fixture type, collection name and page-factory helper from `HotstringsCrudFlowTests.cs` verbatim — do not assume `E2EFixture`/`NewPageAsync`/`BaseUrl` are the real names.

- [ ] **Step 2: Update the mobile flow**

In `tests/AHKFlowApp.E2E.Tests/HotkeysMobileFlowTests.cs`, replace any assertion reading the old `Action`/`Parameters` detail rows with the action chip and summary the expanded row now renders.

- [ ] **Step 3: Run the E2E suite**

Start the worktree stack in two terminals, then:

```bash
dotnet test tests/AHKFlowApp.E2E.Tests --filter "FullyQualifiedName~Hotkeys"
```
Expected: PASS. Worktrees run no-auth (test provider, always signed in), so no login step is needed.

- [ ] **Step 4: Full solution gate**

```bash
dotnet build --configuration Release
dotnet test AHKFlowApp.slnx --configuration Release
dotnet format AHKFlowApp.slnx --verify-no-changes
```
Expected: build clean (`TreatWarningsAsErrors` is on), all tests pass, no format diff.

- [ ] **Step 5: Confirm no legacy references survive**

```bash
grep -rn "HotkeyAction\b\|ParametersFilter\|\.Parameters" src/Frontend/AHKFlowApp.UI.Blazor tests/AHKFlowApp.UI.Blazor.Tests
```
Expected: no matches. Any hit is a missed mirror from Task 2.

- [ ] **Step 6: Commit**

```bash
git add tests/AHKFlowApp.E2E.Tests
git commit -m "test: add hotkey crud e2e flow, update mobile flow for typed actions"
```

---

## Self-Review

**Spec coverage (§3, §4, §9 W1 UI, §10 UI, §11):**
- Dual desktop-grid / mobile-list layout preserved → Tasks 9. ✓
- Combined Action column, chip + combo label, single-sourced via `HotkeyActionDisplay` → Tasks 6, 9. ✓
- Inline edit retained for simplest rows; `IsInlineEditable` extended with key validity so legacy rows route to the dialog → Tasks 5, 9. ✓
- Single edit button routing by capability → Task 9 Step 4. (Spec lists this under W4; pulled forward per §9 W1's own note that a W1 Action column without it leaves simple rows unable to change their action.) ✓
- Key picker backed by the registry, grouped, plus free-typed `vk`/`sc` → Tasks 1, 4, 7. **Grouping is delivered by ordering plus a per-item group label, not by headers** — `MudAutocomplete` 9.3.0 has no `GroupBy`, and `T="HotkeyKeyDto"` would break `CoerceValue` and with it the escape hatch. This is the one place the plan knowingly renders a spec §4 requirement differently than described; the information is present, the visual form differs.
- Action selector as a toggle group of 7 with icon + colour, each revealing its own panel → Task 8. ✓
- SendKeys mini-picker, Run target + kind, Window op select, Remap dest picker, Raw body with brace warning → Task 8 Step 3. ✓
- Live debounced preview panel, copy button, field-mapped errors → Task 8 Steps 3–4. ✓
- Raw safety warning in the exact wording spec §5 demands → Task 6 (`RawWarningText`), rendered in Task 8. ✓
- Description, Apply-to-all + Profiles, Categories via `EntityMultiSelect` → Task 8 Step 3, unchanged from today. ✓
- bUnit dialog/grid tests, E2E hotkey flow → Tasks 7, 8, 9, 10. ✓
- **Out of scope by wave, deliberately:** combo/toggle UI, mouse + wheel picker groups, self-lockout and prefix-suppression warnings (W2); window context panel (W3); OKLCH chip tints, glyph legend, `ahk-v2-syntax.md` rewrite (W4). `CONTEXT.md` W1 terms are backend plan Task 12.

**Placeholder scan:** one deliberate stub — the last test in Task 8 Step 1 (`ValidationError_FromSave_LandsOnItsNamedField`) is a comment-only body, flagged inline with an instruction to write it before implementing. Everything else carries real code, including the full dialog markup in Task 8 Step 3. `Task 9 Step 3` still describes column edits prose-style rather than as a full file listing: that file is 800+ lines and mostly unchanged, so a full rewrite would bury the five real edits — unlike the dialog, which is replaced wholesale.

**MudBlazor API claims, verified against the 9.3.0 MCP docs (not memory):** `MudToggleGroup` has `Vertical` and `Size` but **no wrap parameter** — hence the `::deep` flex-wrap rule. `MudAutocomplete` has `SearchFunc`, `CoerceValue`, `CoerceText`, `ResetValueOnEmptyText`, `ItemTemplate`, `ToStringFunc`, `MaxItems` (default **10**, overridden to `null`), `DebounceInterval` (default 100 ms) — and **no `GroupBy`**. Any parameter not in that list must be re-checked before use.

**Type consistency:** `HotkeyActionKind` member order (SendText, SendKeys, Run, Window, Remap, Disable, Raw) is identical in Task 2's mirror, Task 5's `ActiveFields` switch, Task 6's `Label`/`ChipClass`/`Icon`/`Summary` switches and Task 8's panel switch. `HotkeyEditModel`'s typed property names (`Text`, `SendKeysContent`, `RunTarget`, `RunTargetKind`, `WindowOp`, `RemapDest`, `Body`) match the DTO field names in Task 2 and the `KnownFields` set in Task 8, which is what makes the server's `Input.<Field>` error paths map without a translation table. `IHotkeyKeyCatalog.ForRoleAsync`/`IsValidKey`/`IsLoaded` are declared in Task 4 and consumed with those exact names in Tasks 5, 7 and 9. Role strings (`"HotkeyKey"`, `"SendToken"`, `"RemapDest"`) match the `HotkeyKeyRoles` member names Task 1 serializes.

---

## Resolved during plan review (2026-07-22)

1. **`sc` code width — the design spec is stale, the code is right.** Spec §8 says `sc[0-9a-f]{1,4}`; `HotkeyKeys.cs:69` says `{1,3}` and canonicalizes by padding to width 3 (`sc1` → `sc001`). The W0 *plan* specified `{1,3}` and pinned it with tests, so this was a considered decision that the spec line predates — the same category as the spec's pre-W0 "unescaped" line the backend plan already annotated. A 4-digit code could not canonicalize against width-3 padding anyway. Task 4 mirrors the code. **Follow-up:** correct spec §8's regex to `{1,3}` with a dated note; no code change.
2. **Picker grouping — ordering plus per-item labels, not headers.** `MudAutocomplete` 9.3.0 has no `GroupBy` (that is a `MudSelect` feature), and moving to `T="HotkeyKeyDto"` would break `CoerceValue`, which is what makes the `vk`/`sc` escape hatch work in the same field. `ForRoleAsync` orders by group then name; `ItemTemplate` renders the group as dimmed secondary text via `GroupOf`.
3. **SendKeys brace rule — read the registry flag.** Backend Task 3 confirms `vk`/`sc` codes are valid Send tokens and must be braced (`{vk1B}`), named keys must be braced, single printables are bare — while `RemapDest` is never braced and rejects `{Ctrl}`. `RequiresBracesInSend` covers all three; the earlier `key.Length > 1` proxy is gone.
4. **Add opens the dialog.** A new hotkey must choose an `ActionKind`, which the grid cannot express, so the inline-create path (`_pendingCreate`) retires with this wave (Task 9 Step 4).
5. **Test selectors follow the page's existing split** — buttons are semantic CSS classes (`.add-hotkey`, `.start-edit`, `.commit-edit`), only inputs carry `data-test`. An earlier draft of this plan invented `data-test` hooks for buttons that do not exist.

## Unresolved questions

None. Ready for execution.
