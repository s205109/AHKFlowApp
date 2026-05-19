# Seed Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand dev-only seed data from 3 hotstrings + 0 hotkeys to **12 hotstrings + 12 hotkeys** with the eight default categories. Add `SeedCategoriesCommand`, `SeedHotkeysCommand`, and a combined `SeedAllCommand` (single EF transaction, all-or-nothing). Each seed item is tagged to the appropriate categories.

**Architecture:** Mirrors the existing `SeedHotstringsCommand` pattern. New commands live in `Application/Commands/Dev/`. The combined `SeedAllCommand` wraps the three child handlers in a single `IDbContextTransaction` to guarantee atomicity. `reset=true` performs a bounded, owner-scoped delete-then-insert. All endpoints remain dev-only (404 outside `Development`).

**Tech Stack:** .NET 10, EF Core SQL Server, MediatR, Ardalis.Result, xUnit, FluentAssertions, NSubstitute, Testcontainers.

**Spec:** `docs/superpowers/specs/2026-05-19-seed-expansion-design.md`

**Dependencies:**
- Categories plan must be complete (entity + DbSets + lazy-seed-by-marker behavior + `UserPreference.CategoriesSeededAt`).
- Categories amendment plan (`2026-05-19-categories-amendment.md`) supersedes Tasks 4/5/12/13/19 of the Categories plan.

---

## File Structure

### Create

- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedCategoriesCommand.cs`
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs`
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedAllCommand.cs`
- `src/Backend/AHKFlowApp.Application/DTOs/SeedAllResultDto.cs`
- `tests/AHKFlowApp.Application.Tests/Dev/SeedCategoriesCommandHandlerTests.cs`
- `tests/AHKFlowApp.Application.Tests/Dev/SeedHotkeysCommandHandlerTests.cs`
- `tests/AHKFlowApp.Application.Tests/Dev/SeedAllCommandHandlerTests.cs`
- `tests/AHKFlowApp.Application.Tests/Dev/ThrowOnNthSaveDbContext.cs` (test-only `IAppDbContext` decorator that throws on the Nth `SaveChangesAsync` — used to verify rollback)
- `tests/AHKFlowApp.API.Tests/Dev/SeedAllEndpointTests.cs`

### Modify

- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand.cs` — expand `s_samples` to 12, attach category links, backfill junctions on pre-existing seed rows.
- `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs` — add `Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken)`.
- `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` — implement the new interface method as a pass-through to `Database.BeginTransactionAsync`.
- `src/Backend/AHKFlowApp.API/Controllers/DevController.cs` — add `hotkeys/seed`, `categories/seed`, `seed-all` endpoints.
- `tests/AHKFlowApp.API.Tests/Dev/` — add endpoint tests.

---

## Conventions

Same as prior plans (`SqlContainerFixture` per area; `Substitute.For<ICurrentUser>()`; `FakeTimeProvider`; existing builders). The seed handlers honor the `AppEnvironment.IsDevelopment` gate — return `Result.NotFound()` outside Development (existing pattern in `SeedHotstringsCommand.cs:30-31`).

Each seed handler is **idempotent** when `reset=false`: it skips items that already exist for the user (unique key per entity). `reset=true` deletes the user's owner-scoped rows for that entity first.

---

## Task 1: `SeedCategoriesCommand`

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedCategoriesCommand.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Dev/SeedCategoriesCommandHandlerTests.cs`

- [ ] **Step 1: Handler tests**

```csharp
// tests/AHKFlowApp.Application.Tests/Dev/SeedCategoriesCommandHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dev;

[Collection("DevDb")]
public sealed class SeedCategoriesCommandHandlerTests(DevDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
    private readonly AppEnvironment _devEnv = new(IsDevelopment: true);

    private ICurrentUser User()
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(_ownerOid);
        return u;
    }

    [Fact]
    public async Task Seed_Inserts_EightDefaultCategories_AndMarksUserPreference()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);

        Result<IReadOnlyList<CategoryDto>> result = await sut.Handle(new SeedCategoriesCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(8);
        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(8);

        UserPreference? pref = await ctx.UserPreferences.AsNoTracking().FirstOrDefaultAsync(p => p.OwnerOid == _ownerOid);
        pref.Should().NotBeNull();
        pref!.CategoriesSeededAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public async Task Seed_Idempotent_WhenCategoriesAlreadyExist()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build());
        await ctx.SaveChangesAsync();

        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);

        await sut.Handle(new SeedCategoriesCommand(Reset: false), default);

        // Email was already present; remaining 7 inserted.
        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(8);
    }

    [Fact]
    public async Task Reset_ClearsUserCategories_ThenInserts()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Custom1").Build());
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Custom2").Build());
        var prefBefore = UserPreference.CreateDefault(_ownerOid, _clock);
        prefBefore.MarkCategoriesSeeded(_clock);
        ctx.UserPreferences.Add(prefBefore);
        await ctx.SaveChangesAsync();

        _clock.Advance(TimeSpan.FromMinutes(5));
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);
        await sut.Handle(new SeedCategoriesCommand(Reset: true), default);

        List<string> names = await ctx.Categories.Where(c => c.OwnerOid == _ownerOid).Select(c => c.Name).ToListAsync();
        names.Should().HaveCount(8);
        names.Should().NotContain(["Custom1", "Custom2"]);

        UserPreference pref = await ctx.UserPreferences.AsNoTracking().FirstAsync(p => p.OwnerOid == _ownerOid);
        pref.CategoriesSeededAt.Should().Be(_clock.GetUtcNow()); // re-set
    }

    [Fact]
    public async Task Returns_NotFound_When_NotInDevelopment()
    {
        await using AppDbContext ctx = fx.CreateContext();
        AppEnvironment prodEnv = new(IsDevelopment: false);
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, prodEnv);

        Result<IReadOnlyList<CategoryDto>> result = await sut.Handle(new SeedCategoriesCommand(Reset: false), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

> The `DevDbFixture` is the same shape as `ProfileDbFixture`/`CategoryDbFixture`: a single shared SQL container per `[Collection("DevDb")]`. Create it under `tests/AHKFlowApp.Application.Tests/Dev/DevDbFixture.cs`.

- [ ] **Step 2: Implementation**

```csharp
// src/Backend/AHKFlowApp.Application/Commands/Dev/SeedCategoriesCommand.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: seeds the eight starter categories for the current user.
// Idempotent on (OwnerOid, Name). Also sets UserPreference.CategoriesSeededAt
// so subsequent GET /categories does not lazy-seed again.
public sealed record SeedCategoriesCommand(bool Reset) : IRequest<Result<IReadOnlyList<CategoryDto>>>;

internal sealed class SeedCategoriesCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IRequestHandler<SeedCategoriesCommand, Result<IReadOnlyList<CategoryDto>>>
{
    public static readonly string[] DefaultNames =
    [
        "Autocorrect", "Communication", "DateTime", "Email",
        "Code", "Symbols", "Window Management", "App Launcher",
    ];

    public async Task<Result<IReadOnlyList<CategoryDto>>> Handle(SeedCategoriesCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        if (request.Reset)
        {
            List<Category> existing = await db.Categories
                .Where(c => c.OwnerOid == ownerOid)
                .ToListAsync(ct);
            db.Categories.RemoveRange(existing);
        }

        foreach (string name in DefaultNames)
        {
            bool exists = await db.Categories.AnyAsync(c => c.OwnerOid == ownerOid && c.Name == name, ct);
            if (exists) continue;
            db.Categories.Add(Category.Create(ownerOid, name, clock));
        }

        // Upsert the seed marker so a later GET /categories does not also try to lazy-seed.
        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);
        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            db.UserPreferences.Add(pref);
        }
        if (request.Reset)
        {
            // Force the marker to refresh to the current clock tick.
            // MarkCategoriesSeeded is idempotent on its own (no-op if already set), so we set explicitly.
            db.Entry(pref).Property(p => p.CategoriesSeededAt).CurrentValue = null;
        }
        pref.MarkCategoriesSeeded(clock);

        await db.SaveChangesAsync(ct);

        List<CategoryDto> items = await db.Categories
            .AsNoTracking()
            .Where(c => c.OwnerOid == ownerOid)
            .OrderBy(c => c.Name)
            .Select(c => c.ToDto())
            .ToListAsync(ct);

        return Result.Success<IReadOnlyList<CategoryDto>>(items);
    }
}
```

- [ ] **Step 3: Run + commit**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~SeedCategoriesCommandHandlerTests"
git add src/Backend/AHKFlowApp.Application/Commands/Dev/SeedCategoriesCommand.cs \
        tests/AHKFlowApp.Application.Tests/Dev/SeedCategoriesCommandHandlerTests.cs \
        tests/AHKFlowApp.Application.Tests/Dev/DevDbFixture.cs
git commit -m "feat: SeedCategoriesCommand with marker upsert"
```

---

## Task 2: Expand `SeedHotstringsCommand` to 12 + Categories

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand.cs`
- Modify (or create) tests under `tests/AHKFlowApp.Application.Tests/Dev/`.

Each seed hotstring is paired with one or more category names. The handler looks up the user's categories by name (after the categories have been seeded) and inserts junction rows.

- [ ] **Step 1: Update the sample array**

Replace `s_samples` in `SeedHotstringsCommand.cs:21-26` with the 12-item table from the spec:

```csharp
private static readonly (
    string Trigger,
    string Replacement,
    bool Ending,
    bool InsideWord,
    string[] Categories)[] s_samples =
[
    ("recieve", "receive",                true,  true,  new[] { "Autocorrect" }),
    ("btw",     "by the way",             true,  false, new[] { "Communication" }),
    ("brb",     "be right back",          true,  false, new[] { "Communication" }),
    ("fyi",     "for your information",   true,  false, new[] { "Communication" }),
    ("/today",  "{{date:yyyy-MM-dd}}",    false, false, new[] { "DateTime" }),
    ("/now",    "{{datetime:HH:mm}}",     false, false, new[] { "DateTime" }),
    ("@sig",    "Bart Segers\nbart@segocom.nl\nSegocom", false, false, new[] { "Email" }),
    (";arrow",  "→",                 false, false, new[] { "Symbols" }),
    (";check",  "✓",                 false, false, new[] { "Symbols" }),
    (";shrug",  @"¯\_(ツ)_/¯",            false, false, new[] { "Symbols" }),
    (";e:",     "ë",                 false, false, new[] { "Symbols" }),
    (";todo",   "TODO(name): ",           false, false, new[] { "Code" }),
];
```

The escaped unicode keeps the file ASCII-safe; the persisted Replacement contains the real glyph at runtime (`→` → `→`).

- [ ] **Step 2: Wire category lookup, junction insert, and backfill**

Inside the handler's existing loop, after the exists/skip check, **branch**: if the hotstring already exists, look up its id and backfill any missing junctions; otherwise insert the new entity then attach junctions. Load the user's categories once before the loop:

```csharp
// Before the foreach over s_samples:
Dictionary<string, Guid> categoryByName = await db.Categories
    .Where(c => c.OwnerOid == ownerOid)
    .ToDictionaryAsync(c => c.Name, c => c.Id, ct);

// Existing junction rows for this user's seeded hotstrings, keyed by (hotstringId, categoryId):
HashSet<(Guid HotstringId, Guid CategoryId)> existingLinks = (await db.HotstringCategories
        .Where(hc => hc.Hotstring.OwnerOid == ownerOid)
        .Select(hc => new { hc.HotstringId, hc.CategoryId })
        .ToListAsync(ct))
    .Select(x => (x.HotstringId, x.CategoryId))
    .ToHashSet();

// Inside the loop:
Hotstring? existing = await db.Hotstrings
    .FirstOrDefaultAsync(h => h.OwnerOid == ownerOid && h.Trigger == trigger, ct);

Guid hotstringId;
if (existing is not null)
{
    hotstringId = existing.Id;
}
else
{
    Hotstring entity = Hotstring.Create(ownerOid, trigger, replacement, /* description */ null,
        appliesToAllProfiles: true, isEndingCharacterRequired: ending, isTriggerInsideWord: inside, clock);
    db.Hotstrings.Add(entity);
    hotstringId = entity.Id;
}

foreach (string categoryName in sampleCategories)
{
    if (!categoryByName.TryGetValue(categoryName, out Guid categoryId)) continue;
    if (!existingLinks.Add((hotstringId, categoryId))) continue; // already linked
    db.HotstringCategories.Add(HotstringCategory.Create(hotstringId, categoryId));
}
```

> The `description` parameter on `Hotstring.Create` arrives with the Schema Polish plan. If that plan has not yet landed, omit the parameter and let it default to whatever the current `Create` signature requires. After Schema Polish ships, pass `null`.

**Backfill rationale:** if `seed-hotstrings` runs before `seed-categories`, the 12 rows insert without junctions. A subsequent `seed-hotstrings` (reset=false) MUST find the existing rows by trigger and attach the missing category links — otherwise the broken state is permanent until the user runs `reset=true`. The same branch applies to `SeedHotkeysCommand` (Task 3) — mirror the pattern there.

- [ ] **Step 3: Update tests**

The existing `SeedHotstringsCommand` tests assert 3 entries. Update them to assert 12, and add:

- Each seed entry is attached to its expected categories (count = expected, names match).
- Calling `seed-hotstrings` before `seed-categories` produces 12 hotstrings with **zero** junction rows.
- **Backfill test:** after the standalone call above, calling `seed-categories` then a second `seed-hotstrings` (reset=false) produces 12 hotstrings (no duplicates) **and** correct junctions backfilled onto the existing rows.
- Re-running `seed-hotstrings` twice with categories already present does NOT duplicate junctions (HashSet guard).

- [ ] **Step 4: Run + commit**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~SeedHotstringsCommandHandlerTests"
git add src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand.cs \
        tests/AHKFlowApp.Application.Tests/Dev/
git commit -m "feat: expand SeedHotstrings to 12 with category links"
```

---

## Task 3: `SeedHotkeysCommand`

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Dev/SeedHotkeysCommandHandlerTests.cs`

Mirror `SeedHotstringsCommand` shape. 12 entries from the spec, each with a category list.

- [ ] **Step 1: Handler tests** — assert 12 inserts on first call, idempotent on re-call (no duplicate rows, no duplicate junctions), reset clears prior, 404 outside dev, category junctions present after `seed-categories`, **and** backfill: calling `seed-hotkeys` before `seed-categories` produces 12 rows with zero junctions, then `seed-categories` + a second `seed-hotkeys` (reset=false) leaves 12 rows with correct junctions backfilled.

- [ ] **Step 2: Implementation**

```csharp
// src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

public sealed record SeedHotkeysCommand(bool Reset) : IRequest<Result<PagedList<HotkeyDto>>>;

internal sealed class SeedHotkeysCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IRequestHandler<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>>
{
    private static readonly (
        string Description,
        bool Ctrl, bool Alt, bool Shift, bool Win,
        string Key,
        HotkeyAction Action,
        string Parameters,
        string[] Categories)[] s_samples =
    [
        ("Launch Windows Terminal",  true,  true,  false, false, "T",     HotkeyAction.Run,  "wt.exe",       new[] { "App Launcher" }),
        ("Launch Notepad",           true,  true,  false, false, "N",     HotkeyAction.Run,  "notepad.exe",  new[] { "App Launcher" }),
        ("Launch File Explorer",     true,  true,  false, false, "E",     HotkeyAction.Run,  "explorer.exe", new[] { "App Launcher" }),
        ("Open default browser",     true,  true,  false, false, "B",     HotkeyAction.Run,  "https://",     new[] { "App Launcher" }),
        ("Maximize window",          false, true,  false, true,  "Up",    HotkeyAction.Send, "{Up}",         new[] { "Window Management" }),
        ("Minimize window",          false, true,  false, true,  "Down",  HotkeyAction.Send, "{Down}",       new[] { "Window Management" }),
        ("Snap window left",         false, true,  false, true,  "Left",  HotkeyAction.Send, "{Left}",       new[] { "Window Management" }),
        ("Snap window right",        false, true,  false, true,  "Right", HotkeyAction.Send, "{Right}",      new[] { "Window Management" }),
        ("Paste as plain text",      true,  false, true,  false, "V",     HotkeyAction.Send, "^v",           new[] { "Code" }),
        ("Insert today's date",      true,  true,  false, false, "D",     HotkeyAction.Send, "{{date:yyyy-MM-dd}}", new[] { "DateTime" }),
        ("Lock workstation",         true,  true,  false, false, "L",     HotkeyAction.Run,  "rundll32.exe user32.dll,LockWorkStation", new[] { "App Launcher" }),
        ("Reload AHK script",        true,  true,  false, false, "R",     HotkeyAction.Run,  "Reload",       new[] { "App Launcher" }),
    ];

    public async Task<Result<PagedList<HotkeyDto>>> Handle(SeedHotkeysCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        if (request.Reset)
        {
            List<Hotkey> existing = await db.Hotkeys.Where(h => h.OwnerOid == ownerOid).ToListAsync(ct);
            db.Hotkeys.RemoveRange(existing);
        }

        Dictionary<string, Guid> catByName = await db.Categories
            .Where(c => c.OwnerOid == ownerOid)
            .ToDictionaryAsync(c => c.Name, c => c.Id, ct);

        HashSet<(Guid HotkeyId, Guid CategoryId)> existingLinks = (await db.HotkeyCategories
                .Where(hc => hc.Hotkey.OwnerOid == ownerOid)
                .Select(hc => new { hc.HotkeyId, hc.CategoryId })
                .ToListAsync(ct))
            .Select(x => (x.HotkeyId, x.CategoryId))
            .ToHashSet();

        foreach ((string descr, bool ctrl, bool alt, bool shift, bool win, string key, HotkeyAction action, string param, string[] cats) in s_samples)
        {
            // Backfill branch: find existing seed row by unique key; if missing, insert. Either way, attach missing junctions.
            Hotkey? existing = await db.Hotkeys.FirstOrDefaultAsync(h =>
                h.OwnerOid == ownerOid &&
                h.Key == key &&
                h.Ctrl == ctrl && h.Alt == alt && h.Shift == shift && h.Win == win, ct);

            Guid hotkeyId;
            if (existing is not null)
            {
                hotkeyId = existing.Id;
            }
            else
            {
                Hotkey entity = Hotkey.Create(
                    ownerOid, descr, ctrl, alt, shift, win, key, action, param,
                    appliesToAllProfiles: true, clock);
                db.Hotkeys.Add(entity);
                hotkeyId = entity.Id;
            }

            foreach (string cat in cats)
            {
                if (!catByName.TryGetValue(cat, out Guid cid)) continue;
                if (!existingLinks.Add((hotkeyId, cid))) continue;
                db.HotkeyCategories.Add(HotkeyCategory.Create(hotkeyId, cid));
            }
        }

        await db.SaveChangesAsync(ct);

        List<HotkeyDto> items = await db.Hotkeys
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .OrderBy(h => h.Description)
            .Select(h => h.ToDto())
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotkeyDto>(items, Page: 1, PageSize: items.Count, TotalCount: items.Count));
    }
}
```

> Adjust the `Hotkey.Create(...)` parameter order to match the actual signature in `Hotkey.cs` — inspect first. The example above uses a plausible order; verify before pasting.

- [ ] **Step 3: Run + commit**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~SeedHotkeysCommandHandlerTests"
git add src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotkeysCommand.cs \
        tests/AHKFlowApp.Application.Tests/Dev/SeedHotkeysCommandHandlerTests.cs
git commit -m "feat: SeedHotkeysCommand with 12 samples and category links"
```

---

## Task 4: `SeedAllCommand` — Transactional Orchestration

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedAllCommand.cs`
- Create: `src/Backend/AHKFlowApp.Application/DTOs/SeedAllResultDto.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Dev/SeedAllCommandHandlerTests.cs`

Runs `SeedCategoriesCommand` → `SeedHotstringsCommand` → `SeedHotkeysCommand` inside a single transaction. Rolls back everything on any failure.

- [ ] **Step 1: Result DTO**

```csharp
// src/Backend/AHKFlowApp.Application/DTOs/SeedAllResultDto.cs
namespace AHKFlowApp.Application.DTOs;

public sealed record SeedAllResultDto(
    int CategoriesCount,
    int HotstringsCount,
    int HotkeysCount);
```

- [ ] **Step 2: Handler tests**

```csharp
[Fact]
public async Task SeedAll_Inserts_AllThree_Inside_OneTransaction()
{
    Guid owner = Guid.NewGuid();
    // ... bootstrap fixture and SUT ...

    Result<SeedAllResultDto> result = await sut.Handle(new SeedAllCommand(Reset: false), default);

    result.IsSuccess.Should().BeTrue();
    result.Value.CategoriesCount.Should().Be(8);
    result.Value.HotstringsCount.Should().Be(12);
    result.Value.HotkeysCount.Should().Be(12);

    // assert junctions exist
    (await ctx.HotstringCategories.CountAsync()).Should().BeGreaterOrEqualTo(12);
    (await ctx.HotkeyCategories.CountAsync()).Should().BeGreaterOrEqualTo(12);
}

[Fact]
public async Task SeedAll_Reset_ClearsAll_AndReseeds()
{
    // seed once
    await sut.Handle(new SeedAllCommand(Reset: false), default);
    // seed again with reset
    Result<SeedAllResultDto> result = await sut.Handle(new SeedAllCommand(Reset: true), default);

    result.Value.CategoriesCount.Should().Be(8);
    result.Value.HotstringsCount.Should().Be(12);
    result.Value.HotkeysCount.Should().Be(12);
}

[Fact]
public async Task SeedAll_RollsBack_OnInnerFailure_LeavesNoRows()
{
    // Arrange: build an IAppDbContext decorator that delegates everything to the real ctx
    // but throws on the SECOND SaveChangesAsync call (i.e. after categories have saved,
    // during hotstrings). Register the decorator in the DI container used by this test.
    await using AppDbContext realCtx = fx.CreateContext();
    IAppDbContext failingDb = new ThrowOnNthSaveDbContext(realCtx, failOnCall: 2);

    ServiceCollection services = new();
    services.AddSingleton(failingDb);
    services.AddSingleton<ICurrentUser>(User());
    services.AddSingleton<TimeProvider>(_clock);
    services.AddSingleton(_devEnv);
    services.AddMediatR(cfg => cfg.RegisterServicesFromAssemblyContaining<SeedAllCommand>());
    ServiceProvider sp = services.BuildServiceProvider();
    IMediator mediator = sp.GetRequiredService<IMediator>();

    // Act
    Result<SeedAllResultDto> result = await mediator.Send(new SeedAllCommand(Reset: false));

    // Assert: handler returned an error AND nothing was persisted (transaction rolled back).
    result.IsSuccess.Should().BeFalse();

    await using AppDbContext verify = fx.CreateContext();
    (await verify.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(0);
    (await verify.Hotstrings.CountAsync(h => h.OwnerOid == _ownerOid)).Should().Be(0);
    (await verify.Hotkeys.CountAsync(h => h.OwnerOid == _ownerOid)).Should().Be(0);
}
```

**`ThrowOnNthSaveDbContext`** is a test-only decorator under `tests/AHKFlowApp.Application.Tests/Dev/`. It wraps a real `AppDbContext`, forwards every member of `IAppDbContext` (DbSets, `Entry<T>`, `BeginTransactionAsync`), and increments a counter on each `SaveChangesAsync` call — throwing `InvalidOperationException("forced failure")` when the counter equals `failOnCall`. `BeginTransactionAsync` must return the **real** context's transaction so the rollback actually clears the categories that the first `SaveChangesAsync` flushed.

This test is **required**, not optional — transactional rollback is the central new guarantee of `SeedAllCommand`.

- [ ] **Step 3: Extend `IAppDbContext` with a transaction method (REQUIRED)**

The Application project cannot reference `AppDbContext` — Infrastructure references Application, not the reverse (`AHKFlowApp.Application.csproj` only references Domain). Casting `IAppDbContext` to `AppDbContext` inside Application would not compile. The fix is a one-line interface addition:

```csharp
// src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs
using Microsoft.EntityFrameworkCore.Storage; // add

public interface IAppDbContext
{
    // ... existing members ...

    Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default);
}
```

```csharp
// src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs — add a thin pass-through:
public Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default)
    => Database.BeginTransactionAsync(cancellationToken);
```

No cast, no extra Infrastructure ref from Application.

- [ ] **Step 4: Implementation**

```csharp
// src/Backend/AHKFlowApp.Application/Commands/Dev/SeedAllCommand.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore.Storage;

namespace AHKFlowApp.Application.Commands.Dev;

public sealed record SeedAllCommand(bool Reset) : IRequest<Result<SeedAllResultDto>>;

internal sealed class SeedAllCommandHandler(
    IAppDbContext db,
    IMediator mediator,
    AppEnvironment env)
    : IRequestHandler<SeedAllCommand, Result<SeedAllResultDto>>
{
    public async Task<Result<SeedAllResultDto>> Handle(SeedAllCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        await using IDbContextTransaction tx = await db.BeginTransactionAsync(ct);

        try
        {
            var catResult = await mediator.Send(new SeedCategoriesCommand(request.Reset), ct);
            if (!catResult.IsSuccess) { await tx.RollbackAsync(ct); return Result.Error("seed-all: categories step failed"); }

            var hsResult = await mediator.Send(new SeedHotstringsCommand(request.Reset), ct);
            if (!hsResult.IsSuccess) { await tx.RollbackAsync(ct); return Result.Error("seed-all: hotstrings step failed"); }

            var hkResult = await mediator.Send(new SeedHotkeysCommand(request.Reset), ct);
            if (!hkResult.IsSuccess) { await tx.RollbackAsync(ct); return Result.Error("seed-all: hotkeys step failed"); }

            await tx.CommitAsync(ct);

            return Result.Success(new SeedAllResultDto(
                CategoriesCount: catResult.Value.Count,
                HotstringsCount: hsResult.Value.TotalCount,
                HotkeysCount: hkResult.Value.TotalCount));
        }
        catch (Exception ex)
        {
            await tx.RollbackAsync(ct);
            return Result.Error($"seed-all: rolled back due to {ex.GetType().Name}: {ex.Message}");
        }
    }
}
```

- [ ] **Step 5: Run + commit**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~SeedAllCommandHandlerTests"
git add src/Backend/AHKFlowApp.Application/Commands/Dev/SeedAllCommand.cs \
        src/Backend/AHKFlowApp.Application/DTOs/SeedAllResultDto.cs \
        src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs \
        src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs \
        tests/AHKFlowApp.Application.Tests/Dev/SeedAllCommandHandlerTests.cs \
        tests/AHKFlowApp.Application.Tests/Dev/ThrowOnNthSaveDbContext.cs
git commit -m "feat: SeedAllCommand orchestrates seed pipeline in a single transaction"
```

---

## Task 5: `DevController` Endpoints + Integration Tests

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Controllers/DevController.cs`
- Create: `tests/AHKFlowApp.API.Tests/Dev/SeedAllEndpointTests.cs`

- [ ] **Step 1: Add three endpoints**

```csharp
// in DevController.cs — add alongside existing SeedHotstrings:

/// <summary>Seeds the eight default categories for the authenticated user. Development only.</summary>
[HttpPost("categories/seed")]
[ProducesResponseType(typeof(IReadOnlyList<CategoryDto>), StatusCodes.Status200OK)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
public async Task<ActionResult<IReadOnlyList<CategoryDto>>> SeedCategories(
    [FromQuery] bool reset = false,
    CancellationToken ct = default) =>
    (await mediator.Send(new SeedCategoriesCommand(reset), ct)).ToProblemActionResult(this);

/// <summary>Seeds 12 sample hotkeys for the authenticated user. Development only.</summary>
[HttpPost("hotkeys/seed")]
[ProducesResponseType(typeof(PagedList<HotkeyDto>), StatusCodes.Status200OK)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
public async Task<ActionResult<PagedList<HotkeyDto>>> SeedHotkeys(
    [FromQuery] bool reset = false,
    CancellationToken ct = default) =>
    (await mediator.Send(new SeedHotkeysCommand(reset), ct)).ToProblemActionResult(this);

/// <summary>Runs the full seed pipeline (categories + hotstrings + hotkeys) in a single transaction. Development only.</summary>
[HttpPost("seed-all")]
[ProducesResponseType(typeof(SeedAllResultDto), StatusCodes.Status200OK)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
public async Task<ActionResult<SeedAllResultDto>> SeedAll(
    [FromQuery] bool reset = false,
    CancellationToken ct = default) =>
    (await mediator.Send(new SeedAllCommand(reset), ct)).ToProblemActionResult(this);
```

- [ ] **Step 2: Integration test**

```csharp
// tests/AHKFlowApp.API.Tests/Dev/SeedAllEndpointTests.cs
[Fact]
public async Task SeedAll_ReturnsCountsAnd200_InDevelopment()
{
    HttpClient client = await fx.AuthenticatedClientAsync();

    HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);

    resp.IsSuccessStatusCode.Should().BeTrue();
    SeedAllResultDto? result = await resp.Content.ReadFromJsonAsync<SeedAllResultDto>();
    result.Should().NotBeNull();
    result!.CategoriesCount.Should().Be(8);
    result.HotstringsCount.Should().Be(12);
    result.HotkeysCount.Should().Be(12);
}
```

(Mirror the existing `tests/AHKFlowApp.API.Tests/Dev/` style for bootstrapping `AuthenticatedClientAsync`. If the existing test fixtures don't expose an authenticated client helper, follow whichever pattern is used in the existing seed-hotstrings endpoint test.)

- [ ] **Step 3: Run + commit**

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~SeedAllEndpointTests"
git add src/Backend/AHKFlowApp.API/Controllers/DevController.cs \
        tests/AHKFlowApp.API.Tests/Dev/SeedAllEndpointTests.cs
git commit -m "feat: dev endpoints for categories/hotkeys/seed-all"
```

---

## Task 6: Final Verification

- [ ] **Step 1: Full build + test**

```bash
dotnet build --no-restore
dotnet test --no-build --verbosity normal
```

- [ ] **Step 2: Format**

```bash
dotnet format
git add -u
git commit -m "chore: dotnet format" 2>&1 || echo "nothing to format"
```

- [ ] **Step 3: Manual smoke**

1. Start the stack with a clean dev DB.
2. Authenticate.
3. `POST /api/v1/dev/seed-all?reset=true` — verify 200 with `{ "categoriesCount": 8, "hotstringsCount": 12, "hotkeysCount": 12 }`.
4. `GET /api/v1/categories?pageSize=200` — 8 categories.
5. `GET /api/v1/hotstrings` — 12 items, each with non-empty `categoryIds`.
6. `GET /api/v1/hotkeys` — 12 items, each with non-empty `categoryIds`.
7. Re-call `POST /seed-all?reset=false` — counts remain the same (idempotent).
8. Re-call `POST /seed-all?reset=true` — counts are 8/12/12 again.

---

## Self-Review Checklist

- [ ] Every endpoint returns 404 outside `Development`.
- [ ] `SeedCategoriesCommand` upserts `UserPreference.CategoriesSeededAt` (so subsequent `GET /categories` does not double-seed).
- [ ] `SeedAllCommand` wraps the three steps in a single transaction and rolls back on any failure — verified by `SeedAll_RollsBack_OnInnerFailure_LeavesNoRows` (required, not optional).
- [ ] `IAppDbContext.BeginTransactionAsync` is the only transaction entry point used by Application code; no `AppDbContext` cast anywhere in `src/Backend/AHKFlowApp.Application/`.
- [ ] Re-running `seed-hotstrings` / `seed-hotkeys` after `seed-categories` backfills missing junctions on pre-existing seed rows (verified by backfill test).
- [ ] `Reset=true` is owner-scoped — never touches another user's data.
- [ ] `Reset=true` does **not** touch `Profile` rows (default profile remains).
- [ ] Hotstring/Hotkey samples assert idempotency via unique-key checks per entity.
- [ ] Hotkey `Parameters` placeholders (`{Up}`, `{Down}`, `^v`, etc.) are stored verbatim — they're not real AHK expressions yet; future work expands them.
- [ ] `dotnet format` clean.

---

## Out of Scope

- AHK runtime evaluation of `{{date:fmt}}` placeholders inside seed `Replacement`/`Parameters` — stored as literal text in v1.
- Cross-user template sharing (export/import).
- Per-user override of which 8 categories are seeded — fixed list for v1.
