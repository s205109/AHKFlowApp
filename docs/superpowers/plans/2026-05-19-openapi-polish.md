# OpenAPI / Swagger Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close OpenAPI documentation gaps — annotate the three bare controllers, enable Application-project XML docs in Swagger, and add a CI-level schema test so future drift is caught.

**Architecture:** Foundation already exists (`AddSwaggerGen`, Bearer scheme, XML inclusion of API.xml, `ExampleFilters`). Plan extends it: (a) annotate `WhoAmIController`, (b) add action `<summary>` to `VersionController`/`HealthController`, (c) emit `AHKFlowApp.Application.xml` and wire it into `IncludeXmlComments`, (d) document the public DTO contract surface only, (e) add a schema validation integration test using `Microsoft.OpenApi.Readers`. New controllers added by sibling 2026-05-19 plans (`CategoriesController`, dev `seed-all`, `DownloadsController.Preview`, bulk-delete) ship annotated from those plans — this plan does not touch them.

**Tech Stack:** Swashbuckle.AspNetCore 10.x (already wired), Microsoft.OpenApi.Readers (new test-only package), xUnit + WebApplicationFactory.

---

## Coordination Notes (Out of Scope Here)

These items are spec-required but owned by sibling plans — referenced for clarity, not implemented in this plan:

- `CategoriesController` annotations → `2026-05-19-categories.md` Task 13.
- `DevController.SeedHotkeys` / `SeedAll` annotations → `2026-05-19-seed-expansion.md` Task 5.
- `DownloadsController.Preview` + bulk-delete annotations → `2026-05-19-ux-bundle.md` (not yet planned at time of writing — propagate the requirement when that plan is drafted).

---

## Task 1: Annotate `WhoAmIController`

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Controllers/WhoAmIController.cs`

- [ ] **Step 1: Add class-level auth response types + action `<summary>` + 200 response type**

Replace the controller body (the existing record at the bottom stays unchanged):

```csharp
using AHKFlowApp.Application.Abstractions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status403Forbidden)]
public sealed class WhoAmIController(ICurrentUser currentUser) : ControllerBase
{
    /// <summary>Returns identity claims for the authenticated caller.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(WhoAmIResponse), StatusCodes.Status200OK)]
    public ActionResult<WhoAmIResponse> Get() =>
        Ok(new WhoAmIResponse(currentUser.Oid, currentUser.Email, currentUser.Name, currentUser.IsAuthenticated));
}

public sealed record WhoAmIResponse(Guid? Oid, string? Email, string? Name, bool IsAuthenticated);
```

The signature change (`IActionResult` → `ActionResult<WhoAmIResponse>`) lets Swashbuckle infer the body type even without the explicit attribute, and matches the convention used by every other typed action in this codebase.

- [ ] **Step 2: Build**

Run: `dotnet build src/Backend/AHKFlowApp.API --no-restore`
Expected: PASS.

- [ ] **Step 3: Run existing WhoAmI tests**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~WhoAmI" --no-build`
Expected: PASS (no behavior change — only signature widening and metadata).

- [ ] **Step 4: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Controllers/WhoAmIController.cs
git commit -m "feat(api): annotate WhoAmIController with ProducesResponseType"
```

---

## Task 2: Action `<summary>` on `VersionController` and `HealthController`

These already have `[ProducesResponseType]` — they're missing the XML `<summary>` that other controllers carry. Adding it makes Swagger UI show the operation purpose, not just the URL.

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Controllers/VersionController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs`

- [ ] **Step 1: Add summary to `VersionController.GetVersionAsync`**

Insert immediately above `[HttpGet]`:

```csharp
    /// <summary>Returns the deployed API version (MinVer / informational version).</summary>
```

- [ ] **Step 2: Add summary to `HealthController.GetHealthAsync`**

Insert immediately above `[HttpGet]`:

```csharp
    /// <summary>Aggregates registered health checks. Returns 200 for Healthy or Degraded, 503 for Unhealthy.</summary>
```

- [ ] **Step 3: Build**

Run: `dotnet build src/Backend/AHKFlowApp.API --no-restore`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/Backend/AHKFlowApp.API/Controllers/VersionController.cs \
        src/Backend/AHKFlowApp.API/Controllers/HealthController.cs
git commit -m "docs(api): add XML summary to Version + Health endpoints"
```

---

## Task 3: Emit `AHKFlowApp.Application.xml` and Wire into Swagger

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj`
- Modify: `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs`

- [ ] **Step 1: Enable doc generation on the Application project**

Replace the empty `<PropertyGroup>` at the top of `AHKFlowApp.Application.csproj` with:

```xml
  <PropertyGroup>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
    <!-- We document only the public DTO contract surface (see plan Task 4). Suppress CS1591
         on everything else so the build doesn't drown in noise for handlers/validators/etc. -->
    <NoWarn>$(NoWarn);CS1591</NoWarn>
  </PropertyGroup>
```

`CS1591` suppression is **scoped to this csproj only** — do not put it in `Directory.Build.props`.

- [ ] **Step 2: Wire the Application XML into Swagger**

In `ApiExtensions.AddSwaggerDocs` (lines 51-53), replace the single-file XML inclusion block with one that loads both files when present:

```csharp
            foreach (string assemblyName in new[] { "AHKFlowApp.API", "AHKFlowApp.Application" })
            {
                string xmlPath = Path.Combine(AppContext.BaseDirectory, $"{assemblyName}.xml");
                if (File.Exists(xmlPath))
                    options.IncludeXmlComments(xmlPath, includeControllerXmlComments: true);
            }
```

`includeControllerXmlComments: true` is required on the API file (it owns the controllers); it's harmless on the Application file (no controllers there, the flag is per-file).

- [ ] **Step 3: Build the API**

Run: `dotnet build src/Backend/AHKFlowApp.API --no-restore`
Expected: PASS. The Application project now produces `bin/<Config>/net10.0/AHKFlowApp.Application.xml`, copied to the API output by the project reference.

- [ ] **Step 4: Sanity-check the XML file is emitted**

Run: `dotnet build src/Backend/AHKFlowApp.Application -v:minimal`
Then verify with PowerShell:
`Test-Path src/Backend/AHKFlowApp.Application/bin/Debug/net10.0/AHKFlowApp.Application.xml`
Expected: `True`.

- [ ] **Step 5: Commit**

This is the "wiring" commit — DTO comments land in Task 4.

```bash
git add src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj \
        src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs
git commit -m "feat(api): include Application XML docs in Swagger"
```

---

## Task 4: XML Comments on Application DTOs

In-scope DTOs: every record in `src/Backend/AHKFlowApp.Application/DTOs/`. Each record gets a one-line `<summary>`; each property gets a one-line `<summary>`. Command/query records and validators are **out of scope** — those don't appear in OpenAPI schemas, and adding docs there would re-introduce the CS1591 noise we just suppressed.

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/ProfileDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/DashboardStatsDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/PagedList.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/ProfileScript.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/UserPreferenceDto.cs`

For C# positional record syntax, parameter docs use `<param name="X">…</param>` on the record itself — Swashbuckle reads `<param>` and maps each one to the corresponding schema property. Example template (apply the same shape to every DTO):

- [ ] **Step 1: Annotate `HotstringDto.cs`**

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>A hotstring (text trigger + replacement) owned by the current user.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="ProfileIds">Profiles the hotstring is attached to. Empty when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring is included in every profile the user owns.</param>
/// <param name="Trigger">Abbreviation that activates the replacement (e.g. <c>btw</c>).</param>
/// <param name="Replacement">Text that replaces the trigger (e.g. <c>by the way</c>).</param>
/// <param name="IsEndingCharacterRequired">When true, AutoHotkey requires a trailing whitespace/punctuation character to fire.</param>
/// <param name="IsTriggerInsideWord">When true, the trigger matches even inside a larger word.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
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

/// <summary>Payload to create a new hotstring.</summary>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="ProfileIds">Profiles to attach the new hotstring to. Ignored when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applies to every profile and <paramref name="ProfileIds"/> is ignored.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = true,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);

/// <summary>Payload to replace the editable fields of an existing hotstring.</summary>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="ProfileIds">Replacement profile-attachment set. Ignored when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applies to every profile.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord);
```

- [ ] **Step 2: Annotate `HotkeyDto.cs`**

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>A keyboard hotkey binding owned by the current user.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="ProfileIds">Profiles the hotkey is attached to.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey is included in every profile the user owns.</param>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">The main key (e.g. <c>F1</c>, <c>a</c>).</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific parameter payload (text to send, command to run, etc.).</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
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
    HotkeyAction Action,
    string Parameters,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload to create a new hotkey.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific payload.</param>
/// <param name="ProfileIds">Profiles to attach the new hotkey to.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applies to every profile.</param>
public sealed record CreateHotkeyDto(
    string Description,
    string Key,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    HotkeyAction Action = HotkeyAction.Send,
    string Parameters = "",
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false);

/// <summary>Payload to replace the editable fields of an existing hotkey.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific payload.</param>
/// <param name="ProfileIds">Replacement profile-attachment set.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applies to every profile.</param>
public sealed record UpdateHotkeyDto(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles);
```

- [ ] **Step 3: Annotate `ProfileDto.cs`**

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>A named grouping of hotstrings and hotkeys.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="Name">User-chosen profile name.</param>
/// <param name="IsDefault">True for the user's single default profile.</param>
/// <param name="HeaderTemplate">Liquid-style header injected at the top of the generated <c>.ahk</c> script.</param>
/// <param name="FooterTemplate">Liquid-style footer appended to the generated <c>.ahk</c> script.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
public sealed record ProfileDto(
    Guid Id,
    string Name,
    bool IsDefault,
    string HeaderTemplate,
    string FooterTemplate,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload to create a new profile.</summary>
/// <param name="Name">Profile name. Must be unique per user.</param>
/// <param name="HeaderTemplate">Optional header template; falls back to the application default.</param>
/// <param name="FooterTemplate">Optional footer template; falls back to the application default.</param>
/// <param name="IsDefault">When true, marks this profile as the user's default (clears the flag on any other).</param>
public sealed record CreateProfileDto(
    string Name,
    string? HeaderTemplate = null,
    string? FooterTemplate = null,
    bool IsDefault = false);

/// <summary>Payload to replace the editable fields of an existing profile.</summary>
/// <param name="Name">Profile name. Must be unique per user.</param>
/// <param name="HeaderTemplate">Header template content.</param>
/// <param name="FooterTemplate">Footer template content.</param>
/// <param name="IsDefault">When true, marks this profile as the user's default.</param>
public sealed record UpdateProfileDto(
    string Name,
    string HeaderTemplate,
    string FooterTemplate,
    bool IsDefault);
```

- [ ] **Step 4: Annotate `DashboardStatsDto.cs`**

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>Aggregated stats for the home dashboard.</summary>
/// <param name="Hotstrings">Hotstring totals + recent-creation buckets.</param>
/// <param name="Hotkeys">Hotkey totals + recent-creation buckets.</param>
/// <param name="Profiles">Profile counts (total / active / default).</param>
/// <param name="RecentActivity">Recently created or updated entities, newest first.</param>
public sealed record DashboardStatsDto(
    EntityStatsDto Hotstrings,
    EntityStatsDto Hotkeys,
    ProfileStatsDto Profiles,
    IReadOnlyList<RecentActivityItemDto> RecentActivity);

/// <summary>Counts for an entity kind shown on the dashboard.</summary>
/// <param name="Total">Total number of entities owned by the user.</param>
/// <param name="CreatedThisWeek">Number created in the past 7 days.</param>
/// <param name="DailyBuckets">Per-day creation counts for the past 7 days, oldest first.</param>
public sealed record EntityStatsDto(
    int Total,
    int CreatedThisWeek,
    IReadOnlyList<int> DailyBuckets);

/// <summary>Profile-specific counts for the dashboard.</summary>
/// <param name="Total">Total profiles owned by the user.</param>
/// <param name="Active">Profiles containing at least one hotstring or hotkey.</param>
/// <param name="Default">Always 0 or 1 — number of default profiles.</param>
/// <param name="DailyBuckets">Per-day creation counts for the past 7 days, oldest first.</param>
public sealed record ProfileStatsDto(
    int Total,
    int Active,
    int Default,
    IReadOnlyList<int> DailyBuckets);

/// <summary>A single line in the recent-activity stream.</summary>
/// <param name="Kind">Entity kind (<c>Hotstring</c>, <c>Hotkey</c>, <c>Profile</c>).</param>
/// <param name="Action">Action verb (<c>Created</c>, <c>Updated</c>).</param>
/// <param name="Label">Human-readable label (trigger, description, or profile name).</param>
/// <param name="OccurredAt">UTC timestamp when the action happened.</param>
public sealed record RecentActivityItemDto(
    string Kind,
    string Action,
    string Label,
    DateTimeOffset OccurredAt);
```

- [ ] **Step 5: Annotate `PagedList.cs`**

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>Paginated wrapper for a list response.</summary>
/// <typeparam name="T">Element type.</typeparam>
/// <param name="Items">Page contents.</param>
/// <param name="Page">1-based page number returned.</param>
/// <param name="PageSize">Maximum number of items per page.</param>
/// <param name="TotalCount">Total matching items across all pages.</param>
public sealed record PagedList<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    /// <summary>Total number of pages — <c>ceil(TotalCount / PageSize)</c>.</summary>
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);

    /// <summary>True when a next page exists.</summary>
    public bool HasNextPage => Page < TotalPages;

    /// <summary>True when a previous page exists.</summary>
    public bool HasPreviousPage => Page > 1;
}
```

- [ ] **Step 6: Annotate `ProfileScript.cs`**

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>A rendered AutoHotkey script for a profile.</summary>
/// <param name="FileName">Suggested filename for download (e.g. <c>Work.ahk</c>).</param>
/// <param name="Content">Full script body.</param>
public sealed record ProfileScript(string FileName, string Content);
```

- [ ] **Step 7: Annotate `UserPreferenceDto.cs`**

```csharp
namespace AHKFlowApp.Application.DTOs;

/// <summary>UI preferences for the current user.</summary>
/// <param name="RowsPerPage">Preferred page size in paginated tables.</param>
/// <param name="DarkMode">True when the dark theme is active.</param>
public sealed record UserPreferenceDto(int RowsPerPage, bool DarkMode);

/// <summary>Payload to update UI preferences.</summary>
/// <param name="RowsPerPage">Preferred page size in paginated tables.</param>
/// <param name="DarkMode">True when the dark theme is active.</param>
public sealed record UpdateUserPreferenceDto(int RowsPerPage, bool DarkMode);
```

- [ ] **Step 8: Build the Application project**

Run: `dotnet build src/Backend/AHKFlowApp.Application --no-restore`
Expected: PASS, zero CS1591 warnings (because we suppressed them in Task 3).

- [ ] **Step 9: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/DTOs/
git commit -m "docs(api): XML comments on Application DTOs"
```

---

## Task 5: Schema Validation Integration Test

Catches future drift — a new endpoint shipped without `[ProducesResponseType]` or a DTO change that strips the XML wiring fails the test.

**Files:**
- Modify: `Directory.Packages.props` (add `Microsoft.OpenApi.Readers`).
- Modify: `tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj` (reference it).
- Create: `tests/AHKFlowApp.API.Tests/OpenApi/SwaggerSchemaTests.cs`.

- [ ] **Step 1: Resolve the latest stable `Microsoft.OpenApi.Readers` version**

Run: `dotnet add tests/AHKFlowApp.API.Tests package Microsoft.OpenApi.Readers --no-restore`
This writes a `Version=` attribute into the csproj. Capture the version it picked (let's call it `<VER>`), then **remove the `Version=` attribute** from the csproj (CPM forbids it on consumers).

- [ ] **Step 2: Add the resolved version to `Directory.Packages.props`**

Insert next to the existing `Microsoft.OpenApi`-adjacent or near the `Swashbuckle.AspNetCore` entries (lines 48-49):

```xml
    <PackageVersion Include="Microsoft.OpenApi.Readers" Version="<VER>" />
```

- [ ] **Step 3: Verify the test csproj has a bare `<PackageReference>` only**

After running `dotnet add` it should look like:

```xml
    <PackageReference Include="Microsoft.OpenApi.Readers" />
```

(no `Version=` attribute — CPM resolves it).

- [ ] **Step 4: Write the test**

Create `tests/AHKFlowApp.API.Tests/OpenApi/SwaggerSchemaTests.cs`:

```csharp
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.OpenApi.Models;
using Microsoft.OpenApi.Readers;
using Xunit;

namespace AHKFlowApp.API.Tests.OpenApi;

[Collection("WebApi")]
public sealed class SwaggerSchemaTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task SwaggerJson_EveryOperation_DeclaresAtLeastOne2xxResponse()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();
        await using Stream stream = await client.GetStreamAsync("/swagger/v1/swagger.json");
        OpenApiDocument doc = new OpenApiStreamReader().Read(stream, out _);

        // Act + Assert
        foreach ((string path, OpenApiPathItem pathItem) in doc.Paths)
        {
            foreach ((OperationType verb, OpenApiOperation op) in pathItem.Operations)
            {
                bool has2xx = op.Responses.Keys.Any(code => code.StartsWith('2'));
                has2xx.Should().BeTrue(
                    $"operation {verb} {path} must declare at least one 2xx response via [ProducesResponseType]");
            }
        }
    }

    [Fact]
    public async Task SwaggerJson_HotstringDto_PropertyDescriptionsAreSurfaced()
    {
        // Sanity-check that AHKFlowApp.Application.xml is wired into Swagger.
        // If wiring breaks, schema property descriptions disappear.

        // Arrange
        using HttpClient client = _factory.CreateClient();
        await using Stream stream = await client.GetStreamAsync("/swagger/v1/swagger.json");
        OpenApiDocument doc = new OpenApiStreamReader().Read(stream, out _);

        // Act
        bool found = doc.Components.Schemas.TryGetValue("HotstringDto", out OpenApiSchema? schema);

        // Assert
        found.Should().BeTrue("HotstringDto should be present in the generated schema");
        schema!.Properties.Values
            .Any(p => !string.IsNullOrWhiteSpace(p.Description))
            .Should().BeTrue("at least one HotstringDto property should carry a description from XML docs");
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 5: Restore + build the test project**

Run: `dotnet restore && dotnet build tests/AHKFlowApp.API.Tests --no-restore`
Expected: PASS.

- [ ] **Step 6: Run the new tests**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~SwaggerSchemaTests" --no-build`
Expected: 2 tests PASS.

If `EveryOperation_DeclaresAtLeastOne2xxResponse` fails, the failure message names the offending `VERB /api/...` — fix by adding `[ProducesResponseType]` to that action.

- [ ] **Step 7: Commit**

```bash
git add Directory.Packages.props \
        tests/AHKFlowApp.API.Tests/AHKFlowApp.API.Tests.csproj \
        tests/AHKFlowApp.API.Tests/OpenApi/SwaggerSchemaTests.cs
git commit -m "test(api): OpenAPI schema gate"
```

---

## Task 6: Final Verification

- [ ] **Step 1: Format**

Run: `dotnet format`
Expected: no changes (or auto-applied trivial whitespace).

- [ ] **Step 2: Full build**

Run: `dotnet build --no-restore`
Expected: PASS, zero warnings.

- [ ] **Step 3: Full test suite**

Run: `dotnet test --no-build`
Expected: ALL PASS.

- [ ] **Step 4: Manual Swagger UI sanity check (optional but recommended)**

Run the API:
```powershell
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"
```
Open `http://localhost:5600/swagger`. Confirm:
- `WhoAmI` endpoint shows 200 response with `WhoAmIResponse` schema; 401 + 403 with `ProblemDetails`.
- `Hotstring` schemas show property-level descriptions on the right pane (e.g. `Trigger`, `Replacement`).
- Every controller has at least one operation with a summary line.

- [ ] **Step 5: Push and open PR (if applicable)**

```bash
git push -u origin worktree-improvements
gh pr create --title "OpenAPI polish" --body "..."
```

---

## Self-Review Checklist (Run Before Marking Done)

- [ ] **Spec coverage:** Every spec section (Gaps 1-6, Scope 1-7) maps to a task above. Coordination items (Categories, Seed Expansion, UX Bundle) are explicitly out-of-scope-and-deferred, not silently dropped.
- [ ] **Placeholders:** No `TBD`, `TODO`, "implement later", "appropriate error handling". `<VER>` in Task 5 is intentional and resolved at execution time via `dotnet add`.
- [ ] **Type consistency:** `WhoAmIResponse` shape unchanged; `IncludeXmlComments` per-file flag is consistent; CPM rule (no `Version=` on consumer csproj) honored.
- [ ] **YAGNI:** No `<param>` docs on command/query records, no OAuth2 wiring, no example bodies, no public docs on internal types — all explicitly out of scope per the spec.
- [ ] **Commit granularity:** Wiring (Task 3) and DTO docs (Task 4) are separate commits per the spec's "two PRs" hint, while staying on the same branch.

---

## Unresolved Questions

- OAuth2 auth-code flow in Swagger UI — when? *(default: defer until a first-time API user actually needs it; spec already votes defer)*
- `Microsoft.OpenApi.Readers` exists separately from the `Microsoft.OpenApi` already pulled in by Swashbuckle. Reuse JSON-walk approach instead, drop the new package? *(default: keep — spec asked for it explicitly and the Reader API is cleaner)*
- DTO docs on `WhoAmIResponse` — lives in the API project, not Application/DTOs. Annotate it in Task 1 alongside the attributes, or leave bare? *(default: leave bare for now — record is trivially named and the schema property names match the C# names; revisit if a reviewer asks)*
