# Phase 5: Downloads Endpoints + UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two authenticated download endpoints (`GET /api/v1/downloads/{profileId}` for a single `.ahk`, `GET /api/v1/downloads/zip` for all of the user's profiles bundled) and a Blazor `Pages/Downloads.razor` page with per-row download buttons + a top-level "Download all (zip)" button. Reuses the Phase 4 `AhkScriptGenerator`.

**Architecture:** Two MediatR queries in `Application/Queries/Downloads/`. Both load the per-profile script content via the existing `AhkScriptGenerator`. The bulk handler loads the user's hotstrings/hotkeys + profiles in three round-trips total (no N+1) and partitions in memory. A pure static `AhkFileNaming` helper turns profile names into safe ASCII filenames. The thin `DownloadsController` zips the bulk result in-process and returns `FileContentResult`. The Blazor page fetches bytes via the auth-bearing `HttpClient` and triggers a browser save through a small JS interop helper (anchor `href` would not carry the bearer token).

**Tech Stack:** .NET 10, EF Core 10, MediatR, Ardalis.Result, `System.IO.Compression.ZipArchive`, Blazor WASM + MudBlazor, JS interop for browser save, xUnit + FluentAssertions + Testcontainers + bUnit.

**Maps to backlog:** 027 + 027b.
**Spec:** `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 5).

---

## Locked decisions (resolved before plan)

| # | Decision |
|---|---|
| L1  | **Per-profile content type** = `text/plain; charset=utf-8`. AHK headers may legitimately contain non-ASCII; `Content-Disposition: attachment` already forces download regardless of MIME. |
| L2  | **Bulk content type** = `application/zip` (no charset parameter — binary). |
| L3  | **Filename sanitization rule** (`AhkFileNaming.ToSafeStem`): replace any character not matching `[A-Za-z0-9._-]` with `_`; collapse runs of `_` to one; trim leading/trailing `_`; truncate to 64 chars; if the result is empty, return `"profile"`. Same rule applies to per-profile and zip-entry filenames. |
| L4  | **Filename templates**: per-profile = `ahkflow_{safe_stem}.ahk`. Bulk-zip filename = `ahkflow_scripts.zip` (constant). Zip-entry filenames = `ahkflow_{safe_stem}.ahk`. |
| L5  | **Auth + scoping**: both endpoints require `[Authorize]` + `RequiredScope("access_as_user")`. Per-profile endpoint returns 404 for non-existent or other-user `profileId` (matches Profiles convention — no separate 403 for foreign IDs). |
| L6  | **Page rename**: rebuild placeholder `Pages/Download.razor` → `Pages/Downloads.razor`. Route `/download` → `/downloads`. Update `NavMenu.razor`. (No callers besides nav.) |
| L7  | **Auth-aware browser save**: HTTP fetch through the authenticated `HttpClient`, then JS interop blob save (`wwwroot/js/downloads.js`). Anchor-`href` clicks don't carry the bearer token. |
| L8  | **Bulk-zip query — no N+1**: load `Profiles`, `Hotstrings.Include(Profiles)`, `Hotkeys.Include(Profiles)` once each for the owner; partition in memory using `AppliesToAllProfiles || Profiles.Any(p => p.ProfileId == pid)`. Three round-trips regardless of profile count. |
| L9  | **Zip filename collisions**: profile names are unique per owner (D1), but sanitization is lossy. The bulk handler appends `_2`, `_3`, … to the safe stem (before `.ahk`) when an entry name is already taken. The per-profile endpoint never collides (one file). |
| L10 | **Zero-profile bulk request** = empty `application/zip` (200, zero entries). The Downloads page calls `ProfilesApiClient.ListAsync` first (which lazy-seeds the default profile via `ListProfilesQuery`), so the empty case is rare in practice but explicitly tested. |

---

## Branch Setup

Phase 4 is merged to `main`. Phase 5 branches from `main`:

```powershell
git checkout main
git pull --ff-only
git checkout -b feature/027-downloads
```

(Per project convention: no direct commits to main; everything via PR on a feature branch.)

---

## File Map

| Action | File |
|--------|------|
| Modify | `.claude/backlog/027-download-generated-script-endpoint.md` (pin L1, L3–L7) |
| Modify | `.claude/backlog/027b-bulk-zip-download.md` (pin L2, L4, L8–L10) |
| Create | `src/Backend/AHKFlowApp.Application/DTOs/ProfileScript.cs` |
| Create | `src/Backend/AHKFlowApp.Application/Services/AhkFileNaming.cs` |
| Create | `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateProfileScriptQuery.cs` |
| Create | `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsQuery.cs` |
| Create | `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Services/AhkFileNamingTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateProfileScriptQueryTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateAllProfileScriptsQueryTests.cs` |
| Create | `tests/AHKFlowApp.API.Tests/Downloads/DownloadsEndpointsTests.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/IDownloadsApiClient.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/DownloadsApiClient.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/FileDownload.cs` (small record + JS-interop helper interface) |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/JsFileSaver.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/IFileSaver.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/downloads.js` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/index.html` (load `js/downloads.js`) |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` (register `IDownloadsApiClient` + `IFileSaver` in both auth branches) |
| Delete | `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Download.razor` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Downloads.razor` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor` (`download` → `downloads`, label `Downloads`) |
| Create | `tests/AHKFlowApp.UI.Blazor.Tests/Services/DownloadsApiClientTests.cs` |
| Create | `tests/AHKFlowApp.UI.Blazor.Tests/Pages/DownloadsPageTests.cs` |

No new NuGet packages, no migrations, no Domain/Infrastructure changes.

---

## Task 1: Update backlog 027 + 027b to pin Phase 5 decisions

**Files:**
- Modify: `.claude/backlog/027-download-generated-script-endpoint.md`
- Modify: `.claude/backlog/027b-bulk-zip-download.md`

- [ ] **Step 1: Pin format decisions in `027-download-generated-script-endpoint.md`**

Open `.claude/backlog/027-download-generated-script-endpoint.md`. After the existing `## Acceptance criteria` block, insert a new section before `## Out of scope`:

```markdown
## Format decisions (locked in plan 2026-05-07, Phase 5)

- **Content type**: `text/plain; charset=utf-8` (AHK templates may include non-ASCII; `Content-Disposition: attachment` forces download).
- **Filename**: `ahkflow_{safe_stem}.ahk`. `safe_stem` = profile name with `[^A-Za-z0-9._-]` replaced by `_`, runs of `_` collapsed, leading/trailing `_` trimmed, truncated to 64 chars; empty → `profile`.
- **Auth + scoping**: `[Authorize]` + `RequiredScope("access_as_user")`. 404 for non-existent or other-user `profileId` (no separate 403 for foreign ids — matches Profiles convention).
- **UI**: rebuilds placeholder `Pages/Download.razor` → `Pages/Downloads.razor`; route changes from `/download` to `/downloads`. Auth-aware browser save uses JS interop blob save (anchor href doesn't carry bearer token).
```

- [ ] **Step 2: Pin format decisions in `027b-bulk-zip-download.md`**

Open `.claude/backlog/027b-bulk-zip-download.md`. After the existing `## Acceptance criteria` block, insert before `## Out of scope`:

```markdown
## Format decisions (locked in plan 2026-05-07, Phase 5)

- **Content type**: `application/zip` (binary; no charset).
- **Outer filename**: `ahkflow_scripts.zip` (constant).
- **Entry filenames**: `ahkflow_{safe_stem}.ahk` using the same sanitization rule as backlog 027.
- **Performance**: bulk handler loads `Profiles`, `Hotstrings.Include(Profiles)`, `Hotkeys.Include(Profiles)` once each for the owner and partitions in memory — three round-trips regardless of profile count, no N+1.
- **Collision handling**: when sanitization produces a duplicate entry name, append `_2`, `_3`, … to the stem. Profile names are unique per owner (Phase 1 unique constraint), so collisions only happen via lossy sanitization.
- **Zero-profile request**: returns an empty `application/zip` (200, zero entries). The Downloads page calls `/api/v1/profiles` first (which lazy-seeds the default profile), so this is rare in practice.
```

- [ ] **Step 3: Commit**

```powershell
git add .claude/backlog/027-download-generated-script-endpoint.md .claude/backlog/027b-bulk-zip-download.md
git commit -m "docs(027): pin Phase 5 download endpoint format decisions"
```

---

## Task 2: `ProfileScript` DTO + `AhkFileNaming` helper + unit tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/ProfileScript.cs`
- Create: `src/Backend/AHKFlowApp.Application/Services/AhkFileNaming.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Services/AhkFileNamingTests.cs`

- [ ] **Step 1: Create `ProfileScript` DTO**

```csharp
namespace AHKFlowApp.Application.DTOs;

public sealed record ProfileScript(string FileName, string Content);
```

File: `src/Backend/AHKFlowApp.Application/DTOs/ProfileScript.cs`.

- [ ] **Step 2: Write the failing tests for `AhkFileNaming`**

Create `tests/AHKFlowApp.Application.Tests/Services/AhkFileNamingTests.cs`:

```csharp
using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkFileNamingTests
{
    [Theory]
    [InlineData("Work", "Work")]
    [InlineData("work_2025", "work_2025")]
    [InlineData("dot.name", "dot.name")]
    [InlineData("dash-name", "dash-name")]
    public void ToSafeStem_AsciiSafe_ReturnedUnchanged(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Theory]
    [InlineData("Work / Home", "Work_Home")]              // spaces + slash collapse
    [InlineData("Work\\Home", "Work_Home")]               // backslash
    [InlineData("a:b", "a_b")]                            // colon
    [InlineData("a*b?c", "a_b_c")]                        // wildcard chars
    [InlineData("a..b", "a..b")]                          // dots are safe; not collapsed
    [InlineData("naïve", "na_ve")]                        // non-ASCII → underscore
    public void ToSafeStem_UnsafeChars_ReplacedWithUnderscore(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Theory]
    [InlineData("a___b", "a_b")]
    [InlineData("a   b", "a_b")]
    [InlineData("a/\\b", "a_b")]
    public void ToSafeStem_RunsOfUnderscore_CollapsedToOne(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Theory]
    [InlineData("__work__", "work")]
    [InlineData(" work ", "work")]
    [InlineData("///work", "work")]
    public void ToSafeStem_LeadingTrailingUnderscore_Trimmed(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Fact]
    public void ToSafeStem_EmptyResult_ReturnsProfileFallback() =>
        AhkFileNaming.ToSafeStem("???").Should().Be("profile");

    [Fact]
    public void ToSafeStem_Empty_ReturnsProfileFallback() =>
        AhkFileNaming.ToSafeStem("").Should().Be("profile");

    [Fact]
    public void ToSafeStem_LongerThan64Chars_TruncatedTo64()
    {
        string input = new string('a', 100);

        string output = AhkFileNaming.ToSafeStem(input);

        output.Length.Should().Be(64);
        output.Should().Be(new string('a', 64));
    }

    [Fact]
    public void FileName_FormatsAsAhkflowPrefixWithExtension() =>
        AhkFileNaming.FileName("Work").Should().Be("ahkflow_Work.ahk");

    [Fact]
    public void FileName_AppliesSanitization() =>
        AhkFileNaming.FileName("Work / Home").Should().Be("ahkflow_Work_Home.ahk");
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkFileNamingTests" --verbosity normal
```

Expected: failures (type does not exist yet).

- [ ] **Step 4: Implement `AhkFileNaming`**

Create `src/Backend/AHKFlowApp.Application/Services/AhkFileNaming.cs`:

```csharp
using System.Text;

namespace AHKFlowApp.Application.Services;

public static class AhkFileNaming
{
    private const int MaxStemLength = 64;
    private const string EmptyFallback = "profile";

    public static string ToSafeStem(string profileName)
    {
        if (string.IsNullOrEmpty(profileName))
            return EmptyFallback;

        StringBuilder sb = new(profileName.Length);
        bool prevUnderscore = false;
        foreach (char c in profileName)
        {
            bool safe = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-';
            if (safe)
            {
                sb.Append(c);
                prevUnderscore = false;
            }
            else if (!prevUnderscore)
            {
                sb.Append('_');
                prevUnderscore = true;
            }
        }

        string collapsed = sb.ToString().Trim('_');
        if (collapsed.Length == 0)
            return EmptyFallback;

        return collapsed.Length > MaxStemLength
            ? collapsed[..MaxStemLength]
            : collapsed;
    }

    public static string FileName(string profileName) =>
        $"ahkflow_{ToSafeStem(profileName)}.ahk";
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkFileNamingTests" --verbosity normal
```

Expected: all `AhkFileNamingTests` pass.

- [ ] **Step 6: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/DTOs/ProfileScript.cs src/Backend/AHKFlowApp.Application/Services/AhkFileNaming.cs tests/AHKFlowApp.Application.Tests/Services/AhkFileNamingTests.cs
git commit -m "feat(027): add ProfileScript DTO and AhkFileNaming helper"
```

---

## Task 3: `GenerateProfileScriptQuery` (per-profile handler) + integration test

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateProfileScriptQuery.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateProfileScriptQueryTests.cs`

- [ ] **Step 1: Write the failing integration test**

Create `tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateProfileScriptQueryTests.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Tests.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Queries.Downloads;

[Collection("ScriptGeneratorDb")]
public sealed class GenerateProfileScriptQueryTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AhkScriptGenerator _generator = new();

    private GenerateProfileScriptQueryHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns(oid ?? _ownerOid);
        return new GenerateProfileScriptQueryHandler(ctx, cu, _generator);
    }

    [Fact]
    public async Task Handle_UnknownProfileId_ReturnsNotFound()
    {
        await using AppDbContext ctx = fx.CreateContext();
        GenerateProfileScriptQueryHandler sut = CreateSut(ctx);

        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(Guid.NewGuid()), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_ProfileOwnedByOtherUser_ReturnsNotFound()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Guid otherOwner = Guid.NewGuid();
        Profile theirs = new ProfileBuilder().WithOwner(otherOwner).WithName($"Theirs-{Guid.NewGuid():N}").Build();
        ctx.Profiles.Add(theirs);
        await ctx.SaveChangesAsync();

        GenerateProfileScriptQueryHandler sut = CreateSut(ctx);
        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(theirs.Id), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_OwnedProfile_ReturnsGeneratedScript()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile work = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Work-{Guid.NewGuid():N}")
            .WithHeader("#Requires AutoHotkey v2.0").WithFooter("; end").Build();
        Hotstring hsAny = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(false).WithTriggerInsideWord(true)
            .AppliesToAllProfiles().Build();
        Hotstring hsWork = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("addr").WithReplacement("123 Main St")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(work.Id).Build();
        Hotkey hkAny = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl().WithAlt()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .AppliesToAll().Build();
        ctx.Profiles.Add(work);
        ctx.Hotstrings.AddRange(hsAny, hsWork);
        ctx.Hotkeys.Add(hkAny);
        await ctx.SaveChangesAsync();

        GenerateProfileScriptQueryHandler sut = CreateSut(ctx);
        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(work.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.FileName.Should().StartWith("ahkflow_Work-").And.EndWith(".ahk");
        result.Value.Content.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "::addr::123 Main St\n" +
            ":*?:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "^!n::Run(\"notepad.exe\")\n" +
            "; end");
    }

    [Fact]
    public async Task Handle_AnonymousUser_ReturnsUnauthorized()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns((Guid?)null);
        GenerateProfileScriptQueryHandler sut = new(ctx, cu, _generator);

        Result<ProfileScript> result = await sut.Handle(
            new GenerateProfileScriptQuery(Guid.NewGuid()), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~GenerateProfileScriptQueryTests" --verbosity normal
```

Expected: type does not exist (`GenerateProfileScriptQuery` / `Handler`).

- [ ] **Step 3: Implement the query + handler**

Create `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateProfileScriptQuery.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GenerateProfileScriptQuery(Guid ProfileId) : IRequest<Result<ProfileScript>>;

internal sealed class GenerateProfileScriptQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    AhkScriptGenerator generator)
    : IRequestHandler<GenerateProfileScriptQuery, Result<ProfileScript>>
{
    public async Task<Result<ProfileScript>> Handle(GenerateProfileScriptQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.AsNoTracking().FirstOrDefaultAsync(
            p => p.Id == request.ProfileId && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        Guid pid = profile.Id;

        List<Hotstring> hotstrings = await db.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync(ct);

        List<Hotkey> hotkeys = await db.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync(ct);

        string content = generator.Generate(profile, hotstrings, hotkeys);
        string fileName = AhkFileNaming.FileName(profile.Name);
        return Result.Success(new ProfileScript(fileName, content));
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~GenerateProfileScriptQueryTests" --verbosity normal
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateProfileScriptQuery.cs tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateProfileScriptQueryTests.cs
git commit -m "feat(027): GenerateProfileScriptQuery + handler"
```

---

## Task 4: `GenerateAllProfileScriptsQuery` (bulk handler) + integration test

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsQuery.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateAllProfileScriptsQueryTests.cs`

- [ ] **Step 1: Write the failing tests (no-profiles, multi-profile, collision)**

Create `tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateAllProfileScriptsQueryTests.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Tests.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Queries.Downloads;

[Collection("ScriptGeneratorDb")]
public sealed class GenerateAllProfileScriptsQueryTests(ScriptGeneratorDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AhkScriptGenerator _generator = new();

    private GenerateAllProfileScriptsQueryHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns(oid ?? _ownerOid);
        return new GenerateAllProfileScriptsQueryHandler(ctx, cu, _generator);
    }

    [Fact]
    public async Task Handle_AnonymousUser_ReturnsUnauthorized()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns((Guid?)null);
        GenerateAllProfileScriptsQueryHandler sut = new(ctx, cu, _generator);

        Result<IReadOnlyList<ProfileScript>> result = await sut.Handle(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_NoProfiles_ReturnsEmptyList()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Guid lonelyUser = Guid.NewGuid();
        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx, lonelyUser);

        Result<IReadOnlyList<ProfileScript>> result = await sut.Handle(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task Handle_TwoProfilesMixedAnyAndSpecific_PartitionsCorrectly()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile work = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Work-{Guid.NewGuid():N}")
            .WithHeader("HW").WithFooter("FW").Build();
        Profile personal = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Personal-{Guid.NewGuid():N}")
            .AsDefault(false).WithHeader("HP").WithFooter("FP").Build();
        Hotstring hsAny = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .AppliesToAllProfiles().Build();
        Hotstring hsWork = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("addr").WithReplacement("123 Main St")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .InProfile(work.Id).Build();
        Hotkey hkPersonal = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithDescription("Open Notepad").WithKey("n").WithCtrl()
            .WithAction(HotkeyAction.Run).WithParameters("notepad.exe")
            .InProfile(personal.Id).Build();
        ctx.Profiles.AddRange(work, personal);
        ctx.Hotstrings.AddRange(hsAny, hsWork);
        ctx.Hotkeys.Add(hkPersonal);
        await ctx.SaveChangesAsync();

        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx);
        Result<IReadOnlyList<ProfileScript>> result = await sut.Handle(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(2);

        ProfileScript workScript = result.Value.Single(s => s.FileName.StartsWith("ahkflow_Work-"));
        workScript.Content.Should().Be(
            "HW\n" +
            "; --- Hotstrings ---\n" +
            "::addr::123 Main St\n" +
            "::btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "FW");

        ProfileScript personalScript = result.Value.Single(s => s.FileName.StartsWith("ahkflow_Personal-"));
        personalScript.Content.Should().Be(
            "HP\n" +
            "; --- Hotstrings ---\n" +
            "::btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "^n::Run(\"notepad.exe\")\n" +
            "FP");
    }

    [Fact]
    public async Task Handle_OnlyIncludesCallingUsersProfiles()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Guid otherOwner = Guid.NewGuid();
        Profile mine = new ProfileBuilder().WithOwner(_ownerOid).WithName($"Mine-{Guid.NewGuid():N}").Build();
        Profile theirs = new ProfileBuilder().WithOwner(otherOwner).WithName($"Theirs-{Guid.NewGuid():N}").Build();
        ctx.Profiles.AddRange(mine, theirs);
        await ctx.SaveChangesAsync();

        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx);
        Result<IReadOnlyList<ProfileScript>> result = await sut.Handle(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle()
            .Which.FileName.Should().StartWith("ahkflow_Mine-");
    }

    [Fact]
    public async Task Handle_SanitizationCollision_DisambiguatesWithNumericSuffix()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Guid uniqueOwner = Guid.NewGuid();
        Profile a = new ProfileBuilder().WithOwner(uniqueOwner).WithName("Work/Home").Build();
        Profile b = new ProfileBuilder().WithOwner(uniqueOwner).WithName("Work-Home").AsDefault(false).Build();
        Profile c = new ProfileBuilder().WithOwner(uniqueOwner).WithName("Work\\Home").AsDefault(false).Build();
        ctx.Profiles.AddRange(a, b, c);
        await ctx.SaveChangesAsync();

        GenerateAllProfileScriptsQueryHandler sut = CreateSut(ctx, uniqueOwner);
        Result<IReadOnlyList<ProfileScript>> result = await sut.Handle(
            new GenerateAllProfileScriptsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(3);
        result.Value.Select(s => s.FileName).Distinct().Should().HaveCount(3);
        result.Value.Select(s => s.FileName).Should().BeEquivalentTo(
        [
            "ahkflow_Work_Home.ahk",
            "ahkflow_Work-Home.ahk",     // dash already safe — this one keeps its name
            "ahkflow_Work_Home_2.ahk"     // collision suffix on the second sanitized "Work_Home"
        ]);
    }
}
```

> Note on the collision test: `"Work-Home"` sanitizes to `Work-Home` (dash is in the safe set), so it does NOT collide. `"Work/Home"` and `"Work\\Home"` both sanitize to `Work_Home`, so the second one wins the `_2` suffix. Iteration order is by `Profile.Id` (deterministic for a single test run; the suffix is applied to whichever sorts later, so the assertion uses `BeEquivalentTo` to ignore order).

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~GenerateAllProfileScriptsQueryTests" --verbosity normal
```

Expected: type does not exist.

- [ ] **Step 3: Implement the query + handler**

Create `src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsQuery.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GenerateAllProfileScriptsQuery : IRequest<Result<IReadOnlyList<ProfileScript>>>;

internal sealed class GenerateAllProfileScriptsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    AhkScriptGenerator generator)
    : IRequestHandler<GenerateAllProfileScriptsQuery, Result<IReadOnlyList<ProfileScript>>>
{
    public async Task<Result<IReadOnlyList<ProfileScript>>> Handle(
        GenerateAllProfileScriptsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        // Three round-trips total — load once, partition in memory.
        List<Profile> profiles = await db.Profiles.AsNoTracking()
            .Where(p => p.OwnerOid == ownerOid)
            .OrderBy(p => p.Name)
            .ToListAsync(ct);

        if (profiles.Count == 0)
            return Result.Success<IReadOnlyList<ProfileScript>>([]);

        List<Hotstring> allHotstrings = await db.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .Include(h => h.Profiles)
            .ToListAsync(ct);

        List<Hotkey> allHotkeys = await db.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .Include(h => h.Profiles)
            .ToListAsync(ct);

        List<ProfileScript> scripts = new(profiles.Count);
        HashSet<string> usedNames = new(StringComparer.OrdinalIgnoreCase);

        foreach (Profile profile in profiles)
        {
            Guid pid = profile.Id;

            IEnumerable<Hotstring> hotstringsForProfile = allHotstrings.Where(h =>
                h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid));

            IEnumerable<Hotkey> hotkeysForProfile = allHotkeys.Where(h =>
                h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid));

            string content = generator.Generate(profile, hotstringsForProfile, hotkeysForProfile);
            string fileName = NextUniqueFileName(profile.Name, usedNames);
            scripts.Add(new ProfileScript(fileName, content));
        }

        return Result.Success<IReadOnlyList<ProfileScript>>(scripts);
    }

    private static string NextUniqueFileName(string profileName, HashSet<string> usedNames)
    {
        string baseStem = AhkFileNaming.ToSafeStem(profileName);
        string candidate = $"ahkflow_{baseStem}.ahk";
        int suffix = 2;
        while (!usedNames.Add(candidate))
        {
            candidate = $"ahkflow_{baseStem}_{suffix}.ahk";
            suffix++;
        }
        return candidate;
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~GenerateAllProfileScriptsQueryTests" --verbosity normal
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsQuery.cs tests/AHKFlowApp.Application.Tests/Queries/Downloads/GenerateAllProfileScriptsQueryTests.cs
git commit -m "feat(027b): GenerateAllProfileScriptsQuery + collision-safe filenames"
```

---

## Task 5: `DownloadsController` + integration tests

**Files:**
- Create: `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs`
- Create: `tests/AHKFlowApp.API.Tests/Downloads/DownloadsEndpointsTests.cs`

- [ ] **Step 1: Write the failing integration tests**

Create `tests/AHKFlowApp.API.Tests/Downloads/DownloadsEndpointsTests.cs`:

```csharp
using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Downloads;

[Collection("WebApi")]
public sealed class DownloadsEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    public void Dispose() => _factory.Dispose();

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    private static async Task<ProfileDto> CreateProfileAsync(HttpClient client, string name)
    {
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto(name));
        created.EnsureSuccessStatusCode();
        return (await created.Content.ReadFromJsonAsync<ProfileDto>())!;
    }

    [Fact]
    public async Task GET_per_profile_returns_text_plain_with_attachment_disposition()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Work");

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{profile.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("text/plain");
        response.Content.Headers.ContentType.CharSet.Should().Be("utf-8");
        response.Content.Headers.ContentDisposition!.DispositionType.Should().Be("attachment");
        response.Content.Headers.ContentDisposition.FileName.Should().Be("ahkflow_Work.ahk");
    }

    [Fact]
    public async Task GET_per_profile_body_starts_with_header_template()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Work");

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{profile.Id}");

        string body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("#Requires AutoHotkey v2.0");      // default header
        body.Should().Contain("; --- Hotstrings ---");
        body.Should().Contain("; --- Hotkeys ---");
    }

    [Fact]
    public async Task GET_per_profile_unknown_id_returns_404()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{Guid.NewGuid()}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_per_profile_other_users_id_returns_404()
    {
        using HttpClient theirClient = CreateAuthed(Guid.NewGuid());
        ProfileDto theirProfile = await CreateProfileAsync(theirClient, "Theirs");

        using HttpClient meClient = CreateAuthed();
        HttpResponseMessage response = await meClient.GetAsync($"/api/v1/downloads/{theirProfile.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_per_profile_unauthenticated_returns_401()
    {
        using HttpClient anon = _factory.CreateClient();

        HttpResponseMessage response = await anon.GetAsync($"/api/v1/downloads/{Guid.NewGuid()}");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GET_zip_returns_application_zip_with_attachment_disposition()
    {
        using HttpClient client = CreateAuthed();
        await CreateProfileAsync(client, "Work");
        await CreateProfileAsync(client, "Personal");

        HttpResponseMessage response = await client.GetAsync("/api/v1/downloads/zip");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/zip");
        response.Content.Headers.ContentDisposition!.DispositionType.Should().Be("attachment");
        response.Content.Headers.ContentDisposition.FileName.Should().Be("ahkflow_scripts.zip");
    }

    [Fact]
    public async Task GET_zip_contains_one_entry_per_profile()
    {
        using HttpClient client = CreateAuthed();
        // First call seeds the Default profile lazily
        ProfileDto _ = (await client.GetFromJsonAsync<List<ProfileDto>>("/api/v1/profiles"))!.Single();
        await CreateProfileAsync(client, "Work");
        await CreateProfileAsync(client, "Personal");

        HttpResponseMessage response = await client.GetAsync("/api/v1/downloads/zip");

        await using Stream stream = await response.Content.ReadAsStreamAsync();
        using ZipArchive zip = new(stream, ZipArchiveMode.Read);
        zip.Entries.Select(e => e.Name).Should().BeEquivalentTo(
            "ahkflow_Default.ahk", "ahkflow_Work.ahk", "ahkflow_Personal.ahk");
    }

    [Fact]
    public async Task GET_zip_with_no_profiles_returns_empty_zip()
    {
        // Use a never-before-seen oid that hasn't triggered ListProfilesQuery seeding
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.GetAsync("/api/v1/downloads/zip");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        await using Stream stream = await response.Content.ReadAsStreamAsync();
        using ZipArchive zip = new(stream, ZipArchiveMode.Read);
        zip.Entries.Should().BeEmpty();
    }

    [Fact]
    public async Task GET_zip_unauthenticated_returns_401()
    {
        using HttpClient anon = _factory.CreateClient();

        HttpResponseMessage response = await anon.GetAsync("/api/v1/downloads/zip");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~DownloadsEndpointsTests" --verbosity normal
```

Expected: 404s on every test (no controller).

- [ ] **Step 3: Implement `DownloadsController`**

Create `src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs`:

```csharp
using System.IO.Compression;
using System.Text;
using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using Ardalis.Result;
using MediatR;
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
public sealed class DownloadsController(IMediator mediator) : ControllerBase
{
    private const string AhkContentType = "text/plain; charset=utf-8";
    private const string ZipContentType = "application/zip";
    private const string ZipFileName = "ahkflow_scripts.zip";

    /// <summary>Generated AHK v2 script for a single profile.</summary>
    [HttpGet("{profileId:guid}")]
    [Produces(AhkContentType)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> GetProfile(Guid profileId, CancellationToken ct)
    {
        Result<ProfileScript> result = await mediator.Send(new GenerateProfileScriptQuery(profileId), ct);
        if (!result.IsSuccess)
            return result.ToProblemActionResult(this);

        byte[] bytes = Encoding.UTF8.GetBytes(result.Value.Content);
        return File(bytes, AhkContentType, fileDownloadName: result.Value.FileName);
    }

    /// <summary>Zip containing one .ahk per profile owned by the current user.</summary>
    [HttpGet("zip")]
    [Produces(ZipContentType)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> GetAllZip(CancellationToken ct)
    {
        Result<IReadOnlyList<ProfileScript>> result = await mediator.Send(new GenerateAllProfileScriptsQuery(), ct);
        if (!result.IsSuccess)
            return result.ToProblemActionResult(this);

        byte[] zipBytes;
        using (MemoryStream ms = new())
        {
            using (ZipArchive archive = new(ms, ZipArchiveMode.Create, leaveOpen: true))
            {
                foreach (ProfileScript script in result.Value)
                {
                    ZipArchiveEntry entry = archive.CreateEntry(script.FileName, CompressionLevel.Optimal);
                    using Stream entryStream = entry.Open();
                    using StreamWriter writer = new(entryStream, Encoding.UTF8);
                    await writer.WriteAsync(script.Content);
                }
            }
            zipBytes = ms.ToArray();
        }

        return File(zipBytes, ZipContentType, fileDownloadName: ZipFileName);
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```powershell
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~DownloadsEndpointsTests" --verbosity normal
```

Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```powershell
git add src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs tests/AHKFlowApp.API.Tests/Downloads/DownloadsEndpointsTests.cs
git commit -m "feat(027): DownloadsController with per-profile + bulk zip endpoints"
```

---

## Task 6: Frontend `IDownloadsApiClient` + DI registration + tests

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/FileDownload.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IDownloadsApiClient.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/DownloadsApiClient.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Services/DownloadsApiClientTests.cs`

The client returns the response bytes + filename so the page can hand them off to the JS file saver. Reads `Content-Disposition` to recover the server-chosen filename (don't recompute on the client).

- [ ] **Step 1: Write the failing tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Services/DownloadsApiClientTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class DownloadsApiClientTests
{
    private static DownloadsApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task GetProfileScriptAsync_OnSuccess_ReturnsBytesAndServerFileName()
    {
        var handler = StubHttpMessageHandler.BinaryResponse(
            HttpStatusCode.OK,
            "text/plain; charset=utf-8",
            Encoding.UTF8.GetBytes("script body"),
            fileDownloadName: "ahkflow_Work.ahk");

        ApiResult<FileDownload> result = await ClientWith(handler).GetProfileScriptAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeTrue();
        result.Value!.FileName.Should().Be("ahkflow_Work.ahk");
        result.Value.ContentType.Should().Be("text/plain; charset=utf-8");
        Encoding.UTF8.GetString(result.Value.Content).Should().Be("script body");
    }

    [Fact]
    public async Task GetProfileScriptAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var problem = new ApiProblemDetails(null, "Not Found", 404, "Profile not found", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, problem);

        ApiResult<FileDownload> result = await ClientWith(handler).GetProfileScriptAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    [Fact]
    public async Task GetAllProfileScriptsZipAsync_OnSuccess_ReturnsZipBytesAndFileName()
    {
        byte[] body = [0x50, 0x4B, 0x05, 0x06]; // tiny empty-zip-like marker
        var handler = StubHttpMessageHandler.BinaryResponse(
            HttpStatusCode.OK, "application/zip", body, fileDownloadName: "ahkflow_scripts.zip");

        ApiResult<FileDownload> result = await ClientWith(handler).GetAllProfileScriptsZipAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.FileName.Should().Be("ahkflow_scripts.zip");
        result.Value.ContentType.Should().Be("application/zip");
        result.Value.Content.Should().Equal(body);
    }

    [Fact]
    public async Task GetProfileScriptAsync_NetworkError_ReturnsNetworkErrorResult()
    {
        var handler = StubHttpMessageHandler.ThrowingHandler();

        ApiResult<FileDownload> result = await ClientWith(handler).GetProfileScriptAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NetworkError);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private readonly bool _throw;

        private StubHttpMessageHandler(HttpResponseMessage response, bool @throw = false)
        {
            _response = response;
            _throw = @throw;
        }

        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = System.Net.Http.Json.JsonContent.Create(body) });

        public static StubHttpMessageHandler BinaryResponse(HttpStatusCode status, string contentType, byte[] body, string fileDownloadName)
        {
            var content = new ByteArrayContent(body);
            content.Headers.ContentType = MediaTypeHeaderValue.Parse(contentType);
            content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment") { FileName = fileDownloadName };
            return new(new HttpResponseMessage(status) { Content = content });
        }

        public static StubHttpMessageHandler ThrowingHandler() =>
            new(new HttpResponseMessage(HttpStatusCode.OK), @throw: true);

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            if (_throw) throw new HttpRequestException("Network error");
            return Task.FromResult(_response);
        }
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~DownloadsApiClientTests" --verbosity normal
```

Expected: type does not exist.

- [ ] **Step 3: Create `FileDownload` record + interface + client**

`src/Frontend/AHKFlowApp.UI.Blazor/Services/FileDownload.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.Services;

public sealed record FileDownload(byte[] Content, string FileName, string ContentType);
```

`src/Frontend/AHKFlowApp.UI.Blazor/Services/IDownloadsApiClient.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.Services;

public interface IDownloadsApiClient
{
    Task<ApiResult<FileDownload>> GetProfileScriptAsync(Guid profileId, CancellationToken ct = default);
    Task<ApiResult<FileDownload>> GetAllProfileScriptsZipAsync(CancellationToken ct = default);
}
```

`src/Frontend/AHKFlowApp.UI.Blazor/Services/DownloadsApiClient.cs`:

```csharp
using System.Net;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class DownloadsApiClient(HttpClient httpClient) : IDownloadsApiClient
{
    private const string BasePath = "api/v1/downloads";

    public Task<ApiResult<FileDownload>> GetProfileScriptAsync(Guid profileId, CancellationToken ct = default) =>
        GetFileAsync($"{BasePath}/{profileId}", "ahkflow_profile.ahk", ct);

    public Task<ApiResult<FileDownload>> GetAllProfileScriptsZipAsync(CancellationToken ct = default) =>
        GetFileAsync($"{BasePath}/zip", "ahkflow_scripts.zip", ct);

    private async Task<ApiResult<FileDownload>> GetFileAsync(string path, string fallbackFileName, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, path);
            using HttpResponseMessage resp = await httpClient.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
            {
                ApiProblemDetails? problem = await TryReadProblem(resp, ct);
                return ApiResult<FileDownload>.Failure(MapStatus(resp.StatusCode), problem);
            }

            byte[] bytes = await resp.Content.ReadAsByteArrayAsync(ct);
            string fileName = resp.Content.Headers.ContentDisposition?.FileName?.Trim('"') ?? fallbackFileName;
            string contentType = resp.Content.Headers.ContentType?.ToString() ?? "application/octet-stream";
            return ApiResult<FileDownload>.Ok(new FileDownload(bytes, fileName, contentType));
        }
        catch (HttpRequestException) { return ApiResult<FileDownload>.Failure(ApiResultStatus.NetworkError, null); }
    }

    private static async Task<ApiProblemDetails?> TryReadProblem(HttpResponseMessage resp, CancellationToken ct)
    {
        try { return await resp.Content.ReadFromJsonAsync<ApiProblemDetails>(ct); }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or NotSupportedException or IOException) { return null; }
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

> Note: `DownloadsApiClient` does not extend `ApiClientBase` — that base class assumes JSON responses. The download path needs raw bytes.

You'll need an extra `using System.Net.Http.Json;` in the file if not already pulled in via global usings — add it at the top if the build complains.

- [ ] **Step 4: Register the client in `Program.cs` (BOTH auth branches)**

In `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, find the `useTestAuth` true branch and add after the existing `IProfilesApiClient` registration:

```csharp
    AddApiClient<IDownloadsApiClient, DownloadsApiClient>(
        baseAddress, TimeSpan.FromSeconds(60), useAuth: false);
```

In the `else` (MSAL) branch, add after `IProfilesApiClient`:

```csharp
    AddApiClient<IDownloadsApiClient, DownloadsApiClient>(
        baseAddress, TimeSpan.FromSeconds(60), useAuth: true);
```

(60-second timeout for downloads is generous — zips with many profiles may take a moment.)

- [ ] **Step 5: Run tests to confirm they pass**

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~DownloadsApiClientTests" --verbosity normal
```

Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/Services/FileDownload.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/IDownloadsApiClient.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/DownloadsApiClient.cs src/Frontend/AHKFlowApp.UI.Blazor/Program.cs tests/AHKFlowApp.UI.Blazor.Tests/Services/DownloadsApiClientTests.cs
git commit -m "feat(027): DownloadsApiClient + DI registration"
```

---

## Task 7: JS interop file saver

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/downloads.js`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/index.html`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IFileSaver.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/JsFileSaver.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

- [ ] **Step 1: Create the JS helper**

Create `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/downloads.js`:

```javascript
window.ahkFlowDownloads = {
  saveBlob: function (filename, contentType, base64Bytes) {
    const binary = atob(base64Bytes);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: contentType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
};
```

- [ ] **Step 2: Reference the script from `index.html`**

In `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/index.html`, add a new `<script>` line after the MudBlazor script reference (line 37):

```html
    <script src="js/downloads.js"></script>
```

The block to look for:

```html
    <script src="_content/MudBlazor/MudBlazor.min.js"></script>
    <script>
        if ('serviceWorker' in navigator) {
```

Insert the new line between those two so the file loads on every page.

- [ ] **Step 3: Add the `IFileSaver` abstraction (so the page is bUnit-testable)**

Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/IFileSaver.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.Services;

public interface IFileSaver
{
    Task SaveAsync(string fileName, string contentType, byte[] content);
}
```

Create `src/Frontend/AHKFlowApp.UI.Blazor/Services/JsFileSaver.cs`:

```csharp
using Microsoft.JSInterop;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class JsFileSaver(IJSRuntime js) : IFileSaver
{
    public async Task SaveAsync(string fileName, string contentType, byte[] content)
    {
        string base64 = Convert.ToBase64String(content);
        await js.InvokeVoidAsync("ahkFlowDownloads.saveBlob", fileName, contentType, base64);
    }
}
```

- [ ] **Step 4: Register `IFileSaver` in `Program.cs`**

Near the top of `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, after `builder.Services.AddMudServices();`, add:

```csharp
builder.Services.AddScoped<IFileSaver, JsFileSaver>();
```

- [ ] **Step 5: Build to confirm everything compiles**

```powershell
dotnet build src/Frontend/AHKFlowApp.UI.Blazor --configuration Release
```

Expected: `Build succeeded.`

- [ ] **Step 6: Commit**

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/downloads.js src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/index.html src/Frontend/AHKFlowApp.UI.Blazor/Services/IFileSaver.cs src/Frontend/AHKFlowApp.UI.Blazor/Services/JsFileSaver.cs src/Frontend/AHKFlowApp.UI.Blazor/Program.cs
git commit -m "feat(027): JS interop file saver for auth-aware browser downloads"
```

---

## Task 8: Rebuild `Pages/Downloads.razor` + bUnit tests + nav update

**Files:**
- Delete: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Download.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Downloads.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/DownloadsPageTests.cs`

- [ ] **Step 1: Write the failing bUnit tests**

Create `tests/AHKFlowApp.UI.Blazor.Tests/Pages/DownloadsPageTests.cs`:

```csharp
using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class DownloadsPageTests : BunitContext, IAsyncLifetime
{
    private readonly IProfilesApiClient _profiles = Substitute.For<IProfilesApiClient>();
    private readonly IDownloadsApiClient _downloads = Substitute.For<IDownloadsApiClient>();
    private readonly IFileSaver _saver = Substitute.For<IFileSaver>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public DownloadsPageTests()
    {
        Services.AddSingleton(_profiles);
        Services.AddSingleton(_downloads);
        Services.AddSingleton(_saver);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private IRenderedComponent<Downloads> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<Downloads>(p => p.AddCascadingValue(AuthenticatedState));
    }

    private static ProfileDto MakeProfile(string name) =>
        new(Guid.NewGuid(), name, false, "header", "footer", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private void StubProfileList(params ProfileDto[] profiles) =>
        _profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    [Fact]
    public void Page_OnLoad_RendersTitleAndDownloadAllButton()
    {
        StubProfileList(MakeProfile("Work"));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.download-all").Should().NotBeNull());

        cut.Markup.Should().Contain("Downloads");
        cut.Markup.Should().Contain("Download all");
    }

    [Fact]
    public void Page_OnLoad_RendersOneDownloadButtonPerProfile()
    {
        StubProfileList(MakeProfile("Work"), MakeProfile("Personal"));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.FindAll("button.download-profile").Should().HaveCount(2));
    }

    [Fact]
    public async Task Click_PerProfileDownload_FetchesAndCallsFileSaver()
    {
        ProfileDto work = MakeProfile("Work");
        StubProfileList(work);
        FileDownload payload = new([0x41, 0x42], "ahkflow_Work.ahk", "text/plain; charset=utf-8");
        _downloads.GetProfileScriptAsync(work.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(payload));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.download-profile"));
        cut.Find("button.download-profile").Click();

        await _saver.Received(1).SaveAsync("ahkflow_Work.ahk", "text/plain; charset=utf-8", Arg.Is<byte[]>(b => b.SequenceEqual(payload.Content)));
    }

    [Fact]
    public async Task Click_DownloadAll_FetchesZipAndCallsFileSaver()
    {
        StubProfileList(MakeProfile("Work"));
        FileDownload zip = new([0x50, 0x4B, 0x05, 0x06], "ahkflow_scripts.zip", "application/zip");
        _downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(zip));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.download-all"));
        cut.Find("button.download-all").Click();

        await _saver.Received(1).SaveAsync("ahkflow_scripts.zip", "application/zip", Arg.Is<byte[]>(b => b.SequenceEqual(zip.Content)));
    }

    [Fact]
    public void Page_OnProfileListError_ShowsErrorAlert()
    {
        _profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Failure(ApiResultStatus.NetworkError, null));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("error"));
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~DownloadsPageTests" --verbosity normal
```

Expected: type does not exist (`Downloads` page).

- [ ] **Step 3: Delete the old `Pages/Download.razor`**

```powershell
git rm src/Frontend/AHKFlowApp.UI.Blazor/Pages/Download.razor
```

- [ ] **Step 4: Create `Pages/Downloads.razor`**

`src/Frontend/AHKFlowApp.UI.Blazor/Pages/Downloads.razor`:

```razor
@page "/downloads"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using MudBlazor
@using Microsoft.AspNetCore.Components.Authorization
@implements IDisposable

<PageTitle>Downloads</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Downloads</MudText>

<MudPaper Class="pa-4">
    <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="2" Wrap="Wrap.Wrap" Class="mb-4">
        <MudButton Class="download-all" Variant="Variant.Filled" Color="Color.Primary"
                   StartIcon="@Icons.Material.Filled.Archive"
                   Disabled="@(!_isAuthenticated || _zipLoading || _profiles.Count == 0)"
                   OnClick="DownloadAllAsync">
            Download all (zip)
        </MudButton>
        <MudButton Class="reload-profiles" Variant="Variant.Filled" Color="Color.Secondary"
                   StartIcon="@Icons.Material.Filled.Refresh"
                   Disabled="@(!_isAuthenticated || _loading)"
                   OnClick="ReloadAsync">
            Reload
        </MudButton>
    </MudStack>

    @if (_loadError is not null)
    {
        <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
    }

    <MudTable T="ProfileDto" Items="_profiles" Dense="true" Hover="true" Loading="_loading">
        <HeaderContent>
            <MudTh Style="width:80px">Default</MudTh>
            <MudTh>Name</MudTh>
            <MudTh Style="width:200px">Actions</MudTh>
        </HeaderContent>
        <RowTemplate>
            <MudTd><MudIcon Icon="@(context.IsDefault ? Icons.Material.Filled.Star : Icons.Material.Outlined.StarBorder)" /></MudTd>
            <MudTd>@context.Name</MudTd>
            <MudTd>
                <MudButton Class="download-profile" Variant="Variant.Outlined" Color="Color.Primary"
                           StartIcon="@Icons.Material.Filled.Download"
                           Disabled="@(_busyProfileId == context.Id)"
                           OnClick="() => DownloadProfileAsync(context)">
                    Download
                </MudButton>
            </MudTd>
        </RowTemplate>
        <NoRecordsContent><MudText>No profiles yet.</MudText></NoRecordsContent>
    </MudTable>
</MudPaper>

@code {
    [CascadingParameter] private Task<AuthenticationState>? AuthState { get; set; }
    [Inject] private IProfilesApiClient ProfilesApi { get; set; } = default!;
    [Inject] private IDownloadsApiClient DownloadsApi { get; set; } = default!;
    [Inject] private IFileSaver FileSaver { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;

    private List<ProfileDto> _profiles = [];
    private bool _isAuthenticated;
    private bool _loading;
    private bool _zipLoading;
    private Guid? _busyProfileId;
    private string? _loadError;
    private readonly CancellationTokenSource _cts = new();

    protected override async Task OnInitializedAsync()
    {
        if (AuthState is not null)
        {
            var state = await AuthState;
            _isAuthenticated = state.User.Identity?.IsAuthenticated ?? false;
        }
        if (_isAuthenticated) await ReloadAsync();
    }

    private async Task ReloadAsync()
    {
        _loading = true;
        _loadError = null;
        ApiResult<IReadOnlyList<ProfileDto>> result = await ProfilesApi.ListAsync(_cts.Token);
        _loading = false;

        if (!result.IsSuccess)
        {
            _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
            _profiles = [];
            return;
        }

        _profiles = [.. result.Value!];
    }

    private async Task DownloadProfileAsync(ProfileDto profile)
    {
        _busyProfileId = profile.Id;
        ApiResult<FileDownload> result = await DownloadsApi.GetProfileScriptAsync(profile.Id, _cts.Token);
        _busyProfileId = null;

        if (!result.IsSuccess)
        {
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
            return;
        }

        await FileSaver.SaveAsync(result.Value!.FileName, result.Value.ContentType, result.Value.Content);
        Snackbar.Add($"Downloaded {result.Value.FileName}", Severity.Success);
    }

    private async Task DownloadAllAsync()
    {
        _zipLoading = true;
        ApiResult<FileDownload> result = await DownloadsApi.GetAllProfileScriptsZipAsync(_cts.Token);
        _zipLoading = false;

        if (!result.IsSuccess)
        {
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
            return;
        }

        await FileSaver.SaveAsync(result.Value!.FileName, result.Value.ContentType, result.Value.Content);
        Snackbar.Add($"Downloaded {result.Value.FileName}", Severity.Success);
    }

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

- [ ] **Step 5: Update `Layout/NavMenu.razor`**

In `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`, change:

```razor
    <MudNavLink Href="download"
                Icon="@Icons.Material.Filled.Download">
        Download
    </MudNavLink>
```

to:

```razor
    <MudNavLink Href="downloads"
                Icon="@Icons.Material.Filled.Download">
        Downloads
    </MudNavLink>
```

- [ ] **Step 6: Run tests to confirm they pass**

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~DownloadsPageTests" --verbosity normal
```

Expected: 5 tests pass.

- [ ] **Step 7: Commit**

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Downloads.razor src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor tests/AHKFlowApp.UI.Blazor.Tests/Pages/DownloadsPageTests.cs
# (Pages/Download.razor was deleted via `git rm` in step 3 — already staged)
git commit -m "feat(027): rebuild Downloads page with per-profile + zip buttons"
```

---

## Task 9: Final verification, format, push, PR

- [ ] **Step 1: Full build + format check**

```powershell
dotnet build --configuration Release --no-restore
dotnet format --verify-no-changes
```

Expected: both succeed with no output. If `dotnet format` reports issues, run `dotnet format` (without `--verify-no-changes`), `git add`, then commit as `style(027): apply dotnet format`.

- [ ] **Step 2: Full test pass**

```powershell
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: all suites green — including pre-existing Hotkeys/Hotstrings/Profiles/Health/Auth/Validation tests (no regressions).

- [ ] **Step 3: Manual smoke test (recommended before PR)**

Start the API + Blazor frontend (separate terminals):

```powershell
dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"
dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor
```

Then in the browser:
1. Sign in.
2. Visit `/profiles`, create a second profile (e.g. `Work`).
3. Visit `/hotstrings`, create a hotstring (e.g. `btw` → `by the way`, "Any" checked).
4. Visit `/hotkeys`, create a hotkey (e.g. `Ctrl`+`n`, Run, `notepad.exe`, "Any" checked).
5. Visit `/downloads`. Confirm:
   - Two rows (`Default`, `Work`).
   - Per-row Download saves an `ahkflow_*.ahk` containing the hotstring + hotkey lines.
   - "Download all (zip)" saves `ahkflow_scripts.zip` with two `.ahk` files inside (verify with any zip viewer).
6. Open one of the `.ahk` files in a text editor. Confirm `; --- Hotstrings ---` and `; --- Hotkeys ---` sections, modifier prefix `^` for Ctrl, and `Run("notepad.exe")` syntax.

- [ ] **Step 4: Push and open PR**

```powershell
git push -u origin feature/027-downloads
gh pr create --title "feat(027): per-profile + bulk-zip script downloads" --body "$(cat <<'EOF'
## Summary
- New `GET /api/v1/downloads/{profileId}` returns the AHK v2 script for one profile (`text/plain; charset=utf-8`).
- New `GET /api/v1/downloads/zip` returns `application/zip` of every owner's profile script — no N+1 (three round-trips total).
- Filename sanitization (`AhkFileNaming.ToSafeStem`) collapses unsafe chars to `_`, with `_2`/`_3`… disambiguation for zip-entry collisions.
- Rebuilt `Pages/Downloads.razor` with per-row Download + top-level "Download all (zip)". Auth-aware browser save via JS interop blob (anchor `href` doesn't carry bearer token).
- Phase 4's `AhkScriptGenerator` is reused unchanged.

Maps to backlog: 027 + 027b. Spec: Phase 5 of `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md`.

## Test plan
- [ ] `dotnet test --configuration Release` — all suites green
- [ ] Application unit tests cover `AhkFileNaming` (8 tests) + handler edge cases (NotFound, Unauthorized, owner scoping, collision suffixes)
- [ ] API integration tests cover content-type, content-disposition, 404 / 401, owner scoping, zip entry count, empty-zip
- [ ] Frontend tests cover client byte/filename round-trip and page click → file-saver invocation
- [ ] Manual smoke: per-profile + zip downloads contain correct AHK v2 content
EOF
)"
```

Expected: PR URL printed.

---

## Self-Review

**Spec coverage** (Phase 5 / backlog 027 + 027b):

- ✅ `GET /api/v1/downloads/{profileId}` returns `.ahk` with `Content-Disposition: attachment; filename="ahkflow_{profile_name}.ahk"` — Task 5 (controller + integration test asserts both headers).
- ✅ Endpoint authenticated + scoped to owner; 404 for foreign id — Task 3 (handler returns NotFound) + Task 5 (integration tests for 401 + foreign 404).
- ✅ UI lists profiles with per-row Download — Task 8 (`Downloads.razor` MudTable with `class="download-profile"` MudButton per row + bUnit test asserts count).
- ✅ Integration tests for content-type, filename, auth, owner scoping — Task 5 covers all four.
- ✅ Unit/integration test on controller wiring generator → bytes → headers — Task 5's "starts_with_header_template" + content-type tests (this is what the wiring contract asserts).
- ✅ `GET /api/v1/downloads/zip` returns `application/zip` with `filename="ahkflow_scripts.zip"` — Task 4 (handler) + Task 5 (controller + integration test).
- ✅ One entry per profile, named `ahkflow_{profile_name}.ahk`, sanitized — Task 4 (handler with `NextUniqueFileName` helper + collision test).
- ✅ Authenticated; only calling user's profiles — Task 4 (handler scopes by `OwnerOid`) + Task 5 (integration `GET_zip_unauthenticated_returns_401`).
- ✅ Top-level "Download all (zip)" button — Task 8 (`button.download-all` + bUnit test).
- ✅ Integration test: 2 profiles, hit endpoint, assert entry count + filenames + content matches generator output — Task 5 (`GET_zip_contains_one_entry_per_profile` + per-profile body test).

**Placeholder scan:** none. Every test step has full code; every implementation step has full code; every command is exact.

**Type consistency:**
- `ProfileScript(string FileName, string Content)` is the same record across Tasks 2–8.
- `FileDownload(byte[] Content, string FileName, string ContentType)` consistent in Tasks 6 + 8.
- `IDownloadsApiClient.GetProfileScriptAsync(Guid, CancellationToken) -> ApiResult<FileDownload>` and `GetAllProfileScriptsZipAsync(CancellationToken) -> ApiResult<FileDownload>` match across Tasks 6 + 8.
- `IFileSaver.SaveAsync(string fileName, string contentType, byte[] content)` consistent in Tasks 7 + 8.
- `AhkFileNaming.ToSafeStem(string)` and `AhkFileNaming.FileName(string)` consistent in Tasks 2 + 3 + 4.
- Controller routes: `api/v1/downloads/{profileId:guid}` and `api/v1/downloads/zip` match the integration tests in Task 5.

---

## Unresolved questions

(none — L1–L10 lock the format choices; L8 the perf shape; L9 the collision policy; L10 the empty-profiles behavior)
