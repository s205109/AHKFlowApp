# Hotstrings Redesign — Phase 1 (Foundation + Option Toggles) Implementation Plan

> **Status: completed — merged to `main` (PR #173).** Checkboxes below were not ticked during execution; kept as historical reference.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `HotstringKind` foundation plus two new option toggles (case-sensitive `C`, omit-ending-character `O`) end-to-end — domain, DB, emitter (always-`T` for Text), API, history, CLI, and UI (badge column + dialog options panel + desktop "Edit details").

**Architecture:** Additive flat columns on `Hotstrings` with defaults so every existing row stays a valid Text hotstring. A `HotstringDefinition` parameter record replaces the growing positional factory signatures (one-time call-site churn now; later phases add defaulted record members with zero churn). `HotstringEmitter` is extracted from `AhkScriptGenerator` as the single emission point. All DTO extensions are trailing defaulted members → wire and source compatible.

**Tech Stack:** .NET 10, EF Core 10 + SQL Server (Testcontainers), FluentValidation, Ardalis.Result, Blazor WASM + MudBlazor 9.3, xUnit + FluentAssertions + NSubstitute + bUnit.

**Spec:** `docs/superpowers/specs/2026-07-07-hotstrings-redesign-design.md` (§8 data model, §9 Phase 1 scope, resolved decisions D1–D8).

## Global Constraints

- Work in worktree `C:\Dev\segocom-github\AHKFlowApp\.claude\worktrees\hotstrings-redesign`, branch `feature/hotstrings-redesign`. Run all commands from this root.
- Enum values are wire contract, fixed forever: `Text=0, DateTime=1, Macro=2, Script=3` (spec §8).
- Emitted option order is deterministic: `X * ? C O T`; `O` suppressed when `*` present; `T` always emitted for Text kind (spec D1). `X` arrives in later phases.
- New DTO/snapshot members: trailing positional parameters with defaults (`Kind = HotstringKind.Text`, `IsCaseSensitive = false`, `OmitEndingCharacter = false`) — keeps JSON wire compat (missing props → ctor defaults) and source compat for positional call sites.
- Phase 1 API rejects non-Text `Kind` (validator); kind selector stays hidden in UI (spec D4). No Kind filter/sort in list query (Phase 2).
- CPM: never add `Version=` to `<PackageReference>`; no new packages are needed.
- Patterns: primary constructors, `sealed`, file-scoped namespaces, records for DTOs, explicit mapping (no mapper libs), no repository pattern, `TimeProvider` not `DateTime.Now`.
- Conventional commits, extremely concise. Never `--no-verify`. Never bare `git stash` (shared stash stack — use WIP commits if needed).
- Integration tests need Docker running (Testcontainers SQL Server).
- Before adding/changing MudBlazor markup, verify params via `mcp__mudblazor__get_component_parameters` (pinned MudBlazor 9.3.0) — per `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md`.
- Build/test commands:
  - `dotnet build --configuration Release`
  - `dotnet test tests/<Project> --configuration Release --verbosity normal [--filter ...]`

**Resolved during planning (with user):**
1. Parser accepts bare `T` silently (parse no-op) so the emitter↔parser round-trip stays `Ready`. `C`/`O`/`X` and digit variants (`T0`) still land in `IgnoredFlags` — mapping them is the import follow-up.
2. Desktop gets the "Edit details" dialog button in Phase 1 (otherwise desktop users couldn't edit the new flags once the checkbox columns are gone).

**Deliberate Phase 1 deferrals (do NOT implement):** `DateOffsetUnit`/`WindowMatchType` enums (arrive with their columns in Phases 2/4), kind selector UI, split Add button, Kind filter/sort in list query, CLI create flags (`--case-sensitive` etc.), import mapping of `C`/`O` to columns.

---

### Task 0: Commit this plan to the repo

**Files:**
- Create: `docs/superpowers/plans/2026-07-07-hotstrings-redesign-phase1.md`

- [ ] **Step 1:** Copy this plan file verbatim to `docs/superpowers/plans/2026-07-07-hotstrings-redesign-phase1.md`.
- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-07-07-hotstrings-redesign-phase1.md
git commit -m "docs: phase 1 hotstrings redesign plan"
```

---

### Task 1: Domain foundation — `HotstringKind`, `HotstringDefinition`, entity fields

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Enums/HotstringKind.cs`
- Create: `src/Backend/AHKFlowApp.Domain/Entities/HotstringDefinition.cs`
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (full rewrite below)
- Modify: `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs`
- Modify (mechanical wrap, listed in Step 5): 7 Application call sites + ~15 test files
- Test: `tests/AHKFlowApp.Domain.Tests/Entities/HotstringTests.cs`, `RestoreFactoryTests.cs`

**Interfaces (produced — later tasks depend on these exact shapes):**

```csharp
// AHKFlowApp.Domain.Enums
public enum HotstringKind { Text = 0, DateTime = 1, Macro = 2, Script = 3 }

// AHKFlowApp.Domain.Entities
public sealed record HotstringDefinition(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);

// Hotstring — new signatures + 3 new properties (Kind, IsCaseSensitive, OmitEndingCharacter)
public static Hotstring Create(Guid ownerOid, HotstringDefinition definition, TimeProvider clock);
public static Hotstring Restore(Guid id, Guid ownerOid, HotstringDefinition definition, DateTimeOffset createdAt, TimeProvider clock);
public void Update(HotstringDefinition definition, TimeProvider clock);

// HotstringBuilder — new fluent methods
WithKind(HotstringKind) · WithCaseSensitive(bool) · WithOmitEndingCharacter(bool)
```

- [ ] **Step 1: Write failing domain tests** — append to `tests/AHKFlowApp.Domain.Tests/Entities/HotstringTests.cs` (uses the file's existing `_clock` field):

```csharp
[Fact]
public void Create_DefaultDefinition_IsTextKindWithNewFlagsOff()
{
    var hs = Hotstring.Create(
        Guid.NewGuid(),
        new HotstringDefinition("btw", "by the way", null, true, true, false),
        _clock);

    hs.Kind.Should().Be(HotstringKind.Text);
    hs.IsCaseSensitive.Should().BeFalse();
    hs.OmitEndingCharacter.Should().BeFalse();
}

[Fact]
public void Create_WithNewOptions_SetsKindAndFlags()
{
    var hs = Hotstring.Create(
        Guid.NewGuid(),
        new HotstringDefinition("btw", "by the way", null, true, true, false,
            HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true),
        _clock);

    hs.IsCaseSensitive.Should().BeTrue();
    hs.OmitEndingCharacter.Should().BeTrue();
}

[Fact]
public void Update_WithNewOptions_OverwritesFlags()
{
    var hs = Hotstring.Create(
        Guid.NewGuid(), new HotstringDefinition("x", "y", null, true, true, false), _clock);

    hs.Update(new HotstringDefinition("x", "y", null, true, true, false,
        HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true), _clock);

    hs.IsCaseSensitive.Should().BeTrue();
    hs.OmitEndingCharacter.Should().BeTrue();
}

[Fact]
public void Restore_WithNewOptions_RehydratesFlags()
{
    DateTimeOffset createdAt = DateTimeOffset.UtcNow.AddDays(-1);

    var hs = Hotstring.Restore(
        Guid.NewGuid(), Guid.NewGuid(),
        new HotstringDefinition("x", "y", null, true, true, false,
            HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true),
        createdAt, _clock);

    hs.CreatedAt.Should().Be(createdAt);
    hs.IsCaseSensitive.Should().BeTrue();
    hs.OmitEndingCharacter.Should().BeTrue();
}
```

Add `using AHKFlowApp.Domain.Enums;` to the test file.

- [ ] **Step 2: Verify red** — `dotnet build` → expect CS0246 (`HotstringDefinition` not found) / CS1729.

- [ ] **Step 3: Create the enum**

`src/Backend/AHKFlowApp.Domain/Enums/HotstringKind.cs` (mirrors `HotkeyAction.cs` pattern):

```csharp
namespace AHKFlowApp.Domain.Enums;

public enum HotstringKind
{
    Text = 0,
    DateTime = 1,
    Macro = 2,
    Script = 3,
}
```

- [ ] **Step 4: Create `HotstringDefinition` and rewrite the entity**

`src/Backend/AHKFlowApp.Domain/Entities/HotstringDefinition.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotstring, grouped so factory signatures stay stable
/// as kinds and options grow across the redesign phases.
/// </summary>
public sealed record HotstringDefinition(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);
```

`src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` — full replacement:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class Hotstring
{
    private Hotstring()
    {
        Trigger = string.Empty;
        Replacement = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Trigger { get; private set; }
    public string Replacement { get; private set; }
    public string? Description { get; private set; }
    public bool AppliesToAllProfiles { get; private set; }
    public bool IsEndingCharacterRequired { get; private set; }
    public bool IsTriggerInsideWord { get; private set; }
    public HotstringKind Kind { get; private set; }
    public bool IsCaseSensitive { get; private set; }
    public bool OmitEndingCharacter { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotstringProfile> Profiles { get; private set; } = [];
    public ICollection<HotstringCategory> Categories { get; private set; } = [];

    public static Hotstring Create(Guid ownerOid, HotstringDefinition definition, TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        Hotstring hs = new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            CreatedAt = now,
            UpdatedAt = now,
        };
        hs.Apply(definition);
        return hs;
    }

    public static Hotstring Restore(
        Guid id,
        Guid ownerOid,
        HotstringDefinition definition,
        DateTimeOffset createdAt,
        TimeProvider clock)
    {
        Hotstring hs = new()
        {
            Id = id,
            OwnerOid = ownerOid,
            CreatedAt = createdAt,
            UpdatedAt = clock.GetUtcNow(),
        };
        hs.Apply(definition);
        return hs;
    }

    public void Update(HotstringDefinition definition, TimeProvider clock)
    {
        Apply(definition);
        UpdatedAt = clock.GetUtcNow();
    }

    private void Apply(HotstringDefinition definition)
    {
        Trigger = definition.Trigger;
        Replacement = definition.Replacement;
        Description = definition.Description;
        AppliesToAllProfiles = definition.AppliesToAllProfiles;
        IsEndingCharacterRequired = definition.IsEndingCharacterRequired;
        IsTriggerInsideWord = definition.IsTriggerInsideWord;
        Kind = definition.Kind;
        IsCaseSensitive = definition.IsCaseSensitive;
        OmitEndingCharacter = definition.OmitEndingCharacter;
    }
}
```

- [ ] **Step 5: Update `HotstringBuilder`** — add fields + methods + new `Build()` body in `tests/AHKFlowApp.TestUtilities/Builders/HotstringBuilder.cs`:

```csharp
// new private fields next to the existing ones:
private HotstringKind _kind = HotstringKind.Text;
private bool _isCaseSensitive;
private bool _omitEndingCharacter;

// new fluent methods (same shape as WithTriggerInsideWord):
public HotstringBuilder WithKind(HotstringKind kind)
{
    _kind = kind;
    return this;
}

public HotstringBuilder WithCaseSensitive(bool value)
{
    _isCaseSensitive = value;
    return this;
}

public HotstringBuilder WithOmitEndingCharacter(bool value)
{
    _omitEndingCharacter = value;
    return this;
}

// Build() — replace the Hotstring.Create call:
public Hotstring Build()
{
    var entity = Hotstring.Create(
        _ownerOid,
        new HotstringDefinition(
            _trigger, _replacement, _description, _appliesToAllProfiles,
            _isEndingCharacterRequired, _isTriggerInsideWord,
            _kind, _isCaseSensitive, _omitEndingCharacter),
        _clock);

    foreach (Guid pid in _profileIds)
        entity.Profiles.Add(HotstringProfile.Create(entity.Id, pid));

    foreach (Guid cid in _categoryIds)
        entity.Categories.Add(HotstringCategory.Create(entity.Id, cid));

    return entity;
}
```

Add `using AHKFlowApp.Domain.Enums;`.

- [ ] **Step 6: Mechanically wrap every remaining call site.** Build (`dotnet build`) and fix each CS1501/CS1503. The transformation is always the same — the old positional args `(trigger, replacement, description, appliesToAll, endingRequired, insideWord)` move inside `new HotstringDefinition(...)` in the **same order**; owner/id/createdAt/clock stay outside:

```csharp
// BEFORE
var entity = Hotstring.Create(owner, "btw", "old", null, true, true, true, clock);
// AFTER
var entity = Hotstring.Create(owner, new HotstringDefinition("btw", "old", null, true, true, true), clock);

// BEFORE (Update)
entity.Update(input.Trigger, input.Replacement, description, input.AppliesToAllProfiles,
    input.IsEndingCharacterRequired, input.IsTriggerInsideWord, clock);
// AFTER (Task 4 adds the three input.* fields — here just wrap)
entity.Update(new HotstringDefinition(
    input.Trigger, input.Replacement, description, input.AppliesToAllProfiles,
    input.IsEndingCharacterRequired, input.IsTriggerInsideWord), clock);

// BEFORE (Restore in RestoreHotstringCommand.cs:57)
var entity = Hotstring.Restore(request.Id, ownerOid, snapshot.Trigger, snapshot.Replacement,
    snapshot.Description, snapshot.AppliesToAllProfiles, snapshot.IsEndingCharacterRequired,
    snapshot.IsTriggerInsideWord, snapshot.CreatedAt, clock);
// AFTER (Task 5 adds the three snapshot.* fields — here just wrap)
var entity = Hotstring.Restore(request.Id, ownerOid,
    new HotstringDefinition(snapshot.Trigger, snapshot.Replacement, snapshot.Description,
        snapshot.AppliesToAllProfiles, snapshot.IsEndingCharacterRequired, snapshot.IsTriggerInsideWord),
    snapshot.CreatedAt, clock);
```

⚠️ Two call sites in `tests/AHKFlowApp.Domain.Tests/Entities/HotstringTests.cs` use lower-case named args (`description: null, appliesToAllProfiles: true`) — inside the record ctor the parameter names are PascalCase, so drop the names or use `Description:`/`AppliesToAllProfiles:`.

**src call sites (7):**
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs:67`
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs:74` (`entity.Update`)
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RestoreHotstringCommand.cs:57`
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RevertHotstringCommand.cs` (~line 60, `entity.Update` from snapshot)
- `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/ImportHotstringsCommand.cs:124`
- `src/Backend/AHKFlowApp.Application/Commands/Dev/SeedHotstringsCommand.cs:90`
- `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs:197` (lazy seed)

**test call sites** — enumerate with:

```bash
grep -rn "Hotstring\.\(Create\|Restore\)(" tests/ --include=*.cs
```

Files: `Domain.Tests/Entities/HotstringTests.cs`, `RestoreFactoryTests.cs`, `TestUtilities/Builders/HotstringBuilder.cs` (done in Step 5), `Application.Tests/Hotstrings/{Create,Update,Delete,Get,List*,Import*,Preview*,Seed*}…Tests.cs`, `Application.Tests/Hotstrings/UpdateHotstringWithCategoriesTests.cs`, `Application.Tests/Hotstrings/ListHotstringsLazySeedTests.cs`. All are the simple wrap pattern above.

- [ ] **Step 7: Build clean** — `dotnet build --configuration Release` → 0 errors.
- [ ] **Step 8: Run unit tests** — `dotnet test tests/AHKFlowApp.Domain.Tests --configuration Release` → PASS (incl. 4 new facts). Then `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "Category=Unit"` → PASS.

> Do NOT run integration tests yet — the EF model now has properties the DB lacks, so they are expectedly red until Task 2's migration (which follows immediately). Task 2 Step 6 re-runs them.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: HotstringKind + C/O flags in domain, HotstringDefinition param record"
```

---

### Task 2: Persistence — EF config + migration `AddHotstringKindAndOptionFlags`

**Files:**
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs`
- Generated: `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_AddHotstringKindAndOptionFlags.cs` (+ `.Designer.cs`, snapshot update)
- Test: Create `tests/AHKFlowApp.Infrastructure.Tests/Persistence/HotstringPersistenceTests.cs`

**Interfaces:** columns `Kind int NOT NULL DEFAULT 0`, `IsCaseSensitive bit NOT NULL DEFAULT 0`, `OmitEndingCharacter bit NOT NULL DEFAULT 0` on `Hotstrings`. `IX_Hotstring_Owner_Trigger` unchanged (swap deferred to Phase 4).

- [ ] **Step 1: Write failing persistence test** — `tests/AHKFlowApp.Infrastructure.Tests/Persistence/HotstringPersistenceTests.cs` (mirrors `MigrationTests.cs` context construction):

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class HotstringPersistenceTests(SqlContainerFixture sqlFixture)
{
    [Fact]
    public async Task SaveAndReload_KindAndOptionFlags_RoundTrip()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        Hotstring entity = new HotstringBuilder()
            .WithCaseSensitive(true)
            .WithOmitEndingCharacter(true)
            .Build();

        await using (AppDbContext write = new(options))
        {
            await write.Database.MigrateAsync();
            write.Hotstrings.Add(entity);
            await write.SaveChangesAsync();
        }

        await using AppDbContext read = new(options);
        Hotstring reloaded = await read.Hotstrings.SingleAsync(h => h.Id == entity.Id);

        reloaded.Kind.Should().Be(HotstringKind.Text);
        reloaded.IsCaseSensitive.Should().BeTrue();
        reloaded.OmitEndingCharacter.Should().BeTrue();
    }
}
```

- [ ] **Step 2: Verify red** — `dotnet test tests/AHKFlowApp.Infrastructure.Tests --configuration Release --filter "FullyQualifiedName~HotstringPersistenceTests"` → FAIL (`Invalid column name 'Kind'` — model has properties, DB doesn't).

- [ ] **Step 3: Extend EF configuration** — in `HotstringConfiguration.Configure`, after the `IsTriggerInsideWord` line (line 29):

```csharp
// Persist enum as int (default for EF, made explicit here for clarity).
builder.Property(x => x.Kind)
    .IsRequired()
    .HasConversion<int>();

builder.Property(x => x.IsCaseSensitive).IsRequired();
builder.Property(x => x.OmitEndingCharacter).IsRequired();
```

- [ ] **Step 4: Scaffold migration**

```bash
dotnet ef migrations add AddHotstringKindAndOptionFlags --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Inspect the generated `Up()` — must contain exactly three `AddColumn` calls (alphabetical): `IsCaseSensitive` (`bit`, `nullable: false, defaultValue: false`), `Kind` (`int`, `nullable: false, defaultValue: 0`), `OmitEndingCharacter` (`bit`, `nullable: false, defaultValue: false`) on table `Hotstrings`, and `Down()` drops all three. No index changes. If EF omitted `defaultValue`, add it manually (existing rows must backfill).

- [ ] **Step 5: Verify green** — re-run the Step 2 command → PASS. Also run `dotnet test tests/AHKFlowApp.Infrastructure.Tests --configuration Release` (includes `MigrationTests` idempotency) → PASS.
- [ ] **Step 6: Re-run Application integration tests** — `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release` → PASS.
- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: persist hotstring kind + option flags (migration)"
```

---

### Task 3: `HotstringEmitter` extraction — always-`T`, `C`/`O` emission, parser bare-`T`

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` (delete `FormatHotstring` + `Escape`, delegate)
- Modify: `src/Backend/AHKFlowApp.Application/Services/AhkHotstringParser.cs` (`ParseOptions`, ~line 422)
- Test: `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs`, `Services/AhkScriptGeneratorIntegrationTests.cs`, `Hotstrings/AhkHotstringRoundTripTests.cs`

**Interfaces:**
- Produces: `internal static class HotstringEmitter { public static string Emit(Hotstring hs); }` — Phase 3 preview endpoint reuses this.
- Behavior contract (golden): option order `* ? C O T`; `O` only when ending char required; `T` unconditional (Text is the only kind in Phase 1).

- [ ] **Step 1: Rewrite the options golden Theory (failing first)** — replace `Generate_Hotstring_FormatsOptionsCorrectly` in `AhkScriptGeneratorTests.cs` (lines 51–77):

```csharp
[Theory]
[InlineData(true, false, false, false, ":T:btw::by the way")]    // defaults — Text always emits T (WYSIWYG, D1)
[InlineData(false, false, false, false, ":*T:btw::by the way")]  // expand immediately
[InlineData(true, true, false, false, ":?T:btw::by the way")]    // trigger inside word
[InlineData(true, false, true, false, ":CT:btw::by the way")]    // case sensitive
[InlineData(true, false, false, true, ":OT:btw::by the way")]    // omit ending character
[InlineData(false, false, false, true, ":*T:btw::by the way")]   // O suppressed when *
[InlineData(false, true, true, true, ":*?CT:btw::by the way")]   // deterministic order * ? C O T
public void Generate_Hotstring_FormatsOptionsCorrectly(
    bool isEndingCharacterRequired,
    bool isTriggerInsideWord,
    bool isCaseSensitive,
    bool omitEndingCharacter,
    string expectedLine)
{
    Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
    Hotstring hs = new HotstringBuilder()
        .WithTrigger("btw")
        .WithReplacement("by the way")
        .WithEndingCharacterRequired(isEndingCharacterRequired)
        .WithTriggerInsideWord(isTriggerInsideWord)
        .WithCaseSensitive(isCaseSensitive)
        .WithOmitEndingCharacter(omitEndingCharacter)
        .Build();

    string output = DefaultSut().Generate(profile, [hs], []);

    output.Should().Be(
        "H\n" +
        "; --- Hotstrings ---\n" +
        expectedLine + "\n" +
        "; --- Hotkeys ---\n" +
        "F");
}
```

- [ ] **Step 2: Verify red** — `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~AhkScriptGeneratorTests"` → FAIL (old format emitted).

- [ ] **Step 3: Create the emitter and delegate from the generator**

`src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs`:

```csharp
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotstring lines. Deterministic option order: X * ? C O T
/// (X arrives with non-Text kinds in later phases).
/// </summary>
internal static class HotstringEmitter
{
    public static string Emit(Hotstring hs) =>
        $":{BuildOptions(hs)}:{Escape(hs.Trigger)}::{Escape(hs.Replacement)}";

    private static string BuildOptions(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        if (hs.IsCaseSensitive) options += "C";
        if (hs.OmitEndingCharacter && hs.IsEndingCharacterRequired) options += "O"; // O is meaningless with *
        options += "T"; // Text kind always emits literally (WYSIWYG) — resolved decision D1
        return options;
    }

    // Keep every hotstring on one physical line and its trigger free of characters
    // AHK v2 would otherwise reinterpret (backtick, a whitespace-preceded ';'). Backtick
    // must be escaped first so later escapes are not double-escaped.
    private static string Escape(string value) =>
        value
            .Replace("`", "``")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t")
            .Replace(";", "`;");
}
```

In `AhkScriptGenerator.cs`: delete `FormatHotstring` (lines 49–55) and `Escape` (lines 60–66) with their comment; change the loop body to:

```csharp
foreach (Hotstring hs in hsList)
    lines.Add(HotstringEmitter.Emit(hs));
```

(No DI registration — static class.)

- [ ] **Step 4: Parser accepts bare `T`** — in `AhkHotstringParser.ParseOptions` (line ~422 `switch`), add before the `'S' or 's'` case:

```csharp
case 'T' or 't' when i + 1 >= options.Length || !char.IsDigit(options[i + 1]):
    // Bare T (literal text mode) is the canonical Text-kind emission — a parse no-op.
    // Digit variants (T0/T1) still fall through to the ignored-flags branch below.
    break;
```

- [ ] **Step 5: Fix remaining expected strings.** The transformation rule: in every expected emitted line, insert `T` as the **last** character of the option block — `::trig::` → `:T:trig::`, `:*?:trig::` → `:*?T:trig::`.
  - `AhkScriptGeneratorTests.cs` escape tests (lines ~79–129): e.g. `"::sig::a ``b `; c`n`td`r`ne"` → `":T:sig::a ``b `; c`n`td`r`ne"`.
  - `AhkScriptGeneratorIntegrationTests.cs` full-script golden: `:*?:btw::by the way` → `:*?T:btw::by the way`, default rows `::x::y` → `:T:x::y`.
  - `AhkHotstringRoundTripTests.cs` line 44: `firstScript.Should().Contain(":T:sig::a ``b `; c`n`td`r`ne");` — `Status` stays `Ready` (thanks to Step 4), `secondScript == firstScript` still holds.
  - Check for parser tests that assert `T` lands in ignored flags: `grep -rn '"T"' tests/AHKFlowApp.Application.Tests --include=*.cs` — if a `ParseOptions`/import test expects `IgnoredFlags` containing `"T"` for bare `T`, change it to expect `Ready` with no ignored flag (digit variants `T0`/`T1` keep warning).

- [ ] **Step 6: Verify green** — `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release` → PASS (unit + integration; Docker needed for integration golden).
- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: HotstringEmitter extraction, always-T text emission, C/O flags"
```

---

### Task 4: API surface — DTOs, validators, handlers, list projection

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Mapping/HotstringMappings.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` (inline projection, lines ~146–157)
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs` (validator + handler)
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs` (validator + handler)
- Test: `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandValidatorTests.cs`, `UpdateHotstringCommandValidatorTests.cs`, `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs`

**Interfaces:**
- Produces (wire contract — UI Task 7 and CLI Task 6 mirror these): `HotstringDto` gains trailing `HotstringKind Kind = HotstringKind.Text, bool IsCaseSensitive = false, bool OmitEndingCharacter = false` (after `CategoryIds`); same trailing trio on `CreateHotstringDto` and `UpdateHotstringDto`. Enums serialize as **numbers** (no `JsonStringEnumConverter` configured).
- Validation: `Input.Kind` must be `HotstringKind.Text`, message `"Only Text hotstrings are supported."`

- [ ] **Step 1: Write failing validator tests** — append to `CreateHotstringCommandValidatorTests.cs`:

```csharp
[Fact]
public void Kind_Text_Passes()
{
    CreateHotstringCommand cmd = new(new CreateHotstringDto("btw", "by the way", Kind: HotstringKind.Text));

    var result = _sut.Validate(cmd);

    result.Errors.Should().NotContain(e => e.PropertyName == "Input.Kind");
}

[Fact]
public void Kind_NonText_Fails()
{
    CreateHotstringCommand cmd = new(new CreateHotstringDto("btw", "by the way", Kind: HotstringKind.Script));

    var result = _sut.Validate(cmd);

    result.Errors.Should().Contain(e =>
        e.PropertyName == "Input.Kind" &&
        e.ErrorMessage == "Only Text hotstrings are supported.");
}
```

And to `UpdateHotstringCommandValidatorTests.cs`:

```csharp
[Fact]
public void Kind_NonText_Fails()
{
    UpdateHotstringCommand cmd = new(Guid.NewGuid(),
        new UpdateHotstringDto("btw", "x", null, true, true, true, null, null, HotstringKind.DateTime));

    var result = _sut.Validate(cmd);

    result.Errors.Should().Contain(e =>
        e.PropertyName == "Input.Kind" &&
        e.ErrorMessage == "Only Text hotstrings are supported.");
}
```

Add `using AHKFlowApp.Domain.Enums;` to both test files.

- [ ] **Step 2: Verify red** — `dotnet build` → CS1739/CS1501 (`Kind` not a parameter).

- [ ] **Step 3: Extend the three Application DTO records** in `DTOs/HotstringDto.cs` (add `using AHKFlowApp.Domain.Enums;`; keep existing XML docs, add trailing members):

```csharp
public sealed record HotstringDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Trigger,
    string Replacement,
    string? Description,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[] CategoryIds,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = true,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true,
    string? Description = null,
    Guid[]? CategoryIds = null,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);

public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string? Description,
    Guid[]? CategoryIds = null,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);
```

- [ ] **Step 4: Add validator rule** to **both** `CreateHotstringCommandValidator` and `UpdateHotstringCommandValidator` (after the Description rule):

```csharp
RuleFor(x => x.Input.Kind)
    .Must(k => k == HotstringKind.Text)
    .WithMessage("Only Text hotstrings are supported.");
```

(`using AHKFlowApp.Domain.Enums;` where missing.)

- [ ] **Step 5: Verify validator tests green** — `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~CommandValidatorTests"` → PASS.

- [ ] **Step 6: Thread new fields through handlers and mappings.**

`CreateHotstringCommand.cs` handler (the Task 1 wrap gains the three fields):

```csharp
var entity = Hotstring.Create(
    ownerOid,
    new HotstringDefinition(
        input.Trigger, input.Replacement, description, input.AppliesToAllProfiles,
        input.IsEndingCharacterRequired, input.IsTriggerInsideWord,
        input.Kind, input.IsCaseSensitive, input.OmitEndingCharacter),
    clock);
```

`UpdateHotstringCommand.cs` handler:

```csharp
entity.Update(
    new HotstringDefinition(
        input.Trigger, input.Replacement, description, input.AppliesToAllProfiles,
        input.IsEndingCharacterRequired, input.IsTriggerInsideWord,
        input.Kind, input.IsCaseSensitive, input.OmitEndingCharacter),
    clock);
```

`Mapping/HotstringMappings.cs` — append three args:

```csharp
public static HotstringDto ToDto(this Hotstring h) => new(
    h.Id,
    h.Profiles.Select(p => p.ProfileId).ToArray(),
    h.AppliesToAllProfiles,
    h.Trigger,
    h.Replacement,
    h.Description,
    h.IsEndingCharacterRequired,
    h.IsTriggerInsideWord,
    h.CreatedAt,
    h.UpdatedAt,
    h.Categories.Select(hc => hc.CategoryId).ToArray(),
    h.Kind,
    h.IsCaseSensitive,
    h.OmitEndingCharacter);
```

`ListHotstringsQuery.cs` inline projection (lines ~146–157) — append the same three (`h.Kind, h.IsCaseSensitive, h.OmitEndingCharacter`) after the `CategoryIds` arg.

- [ ] **Step 7: Write failing API integration tests** — append to `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs` (add `using AHKFlowApp.Domain.Enums;`):

```csharp
[Fact]
public async Task Post_WithNewOptionFlags_RoundTripsKindAndFlags()
{
    using HttpClient client = CreateAuthed();
    CreateHotstringDto dto = new("csflags", "x", IsCaseSensitive: true, OmitEndingCharacter: true);

    HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

    response.StatusCode.Should().Be(HttpStatusCode.Created);
    HotstringDto? body = await response.Content.ReadFromJsonAsync<HotstringDto>();
    body!.Kind.Should().Be(HotstringKind.Text);
    body.IsCaseSensitive.Should().BeTrue();
    body.OmitEndingCharacter.Should().BeTrue();

    HttpResponseMessage get = await client.GetAsync(response.Headers.Location);
    HotstringDto? fetched = await get.Content.ReadFromJsonAsync<HotstringDto>();
    fetched!.IsCaseSensitive.Should().BeTrue();
    fetched.OmitEndingCharacter.Should().BeTrue();
}

[Fact]
public async Task Post_NonTextKind_Returns400()
{
    using HttpClient client = CreateAuthed();
    CreateHotstringDto dto = new("scr", "x", Kind: HotstringKind.Script);

    HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

    response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
}
```

- [ ] **Step 8: Run** — `dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~HotstringsEndpointsTests"` → PASS. Then full `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release` → PASS.
- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: kind + option flags through DTOs, validators, API"
```

---

### Task 5: History — snapshot round-trip of new fields

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HistorySnapshots.cs` (`HotstringSnapshot`)
- Modify: `src/Backend/AHKFlowApp.Application/Services/EntityHistoryRecorder.cs` (snapshot construction, lines ~30–40)
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RestoreHotstringCommand.cs`, `RevertHotstringCommand.cs` (add three `snapshot.*` args into the Task-1 `HotstringDefinition`)
- Check: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringHistoryVersionQuery.cs` (lines ~35–39)
- Test: Create `tests/AHKFlowApp.Application.Tests/History/HotstringSnapshotCompatibilityTests.cs`, Create `tests/AHKFlowApp.Application.Tests/History/HotstringNewFieldHistoryTests.cs`

**Interfaces:**
- Produces: `HotstringSnapshot` gains trailing `HotstringKind Kind = HotstringKind.Text, bool IsCaseSensitive = false, bool OmitEndingCharacter = false` — pre-migration JSON (missing members) deserializes to Text defaults via ctor defaults (STJ behavior).

- [ ] **Step 1: Write failing legacy-compat test** — `tests/AHKFlowApp.Application.Tests/History/HotstringSnapshotCompatibilityTests.cs`:

```csharp
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Trait("Category", "Unit")]
public sealed class HotstringSnapshotCompatibilityTests
{
    [Fact]
    public void Deserialize_LegacyJsonWithoutNewFields_DefaultsToTextKind()
    {
        // Pre-Phase-1 snapshot JSON — exactly the members EntityHistoryRecorder wrote before.
        const string legacyJson =
            """
            {"Trigger":"btw","Replacement":"by the way","Description":null,"AppliesToAllProfiles":true,"IsEndingCharacterRequired":true,"IsTriggerInsideWord":false,"ProfileIds":[],"CategoryIds":[],"CreatedAt":"2026-01-01T00:00:00+00:00","UpdatedAt":"2026-01-02T00:00:00+00:00"}
            """;

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(legacyJson);

        snapshot!.Kind.Should().Be(HotstringKind.Text);
        snapshot.IsCaseSensitive.Should().BeFalse();
        snapshot.OmitEndingCharacter.Should().BeFalse();
    }
}
```

- [ ] **Step 2: Verify red** — compile error (`Kind` not on snapshot): `dotnet build`.

- [ ] **Step 3: Extend the snapshot record** in `HistorySnapshots.cs` (add `using AHKFlowApp.Domain.Enums;`):

```csharp
public sealed record HotstringSnapshot(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);
```

Do NOT bump `EntityHistoryRecorder.CurrentSchemaVersion` — defaults make old JSON forward-compatible; version bump is unnecessary churn.

- [ ] **Step 4: Verify compat test green** — `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~HotstringSnapshotCompatibilityTests"` → PASS.

- [ ] **Step 5: Thread fields through recorder + both handlers.**

`EntityHistoryRecorder.cs` snapshot construction — append after `entity.UpdatedAt`:

```csharp
HotstringSnapshot snapshot = new(
    entity.Trigger,
    entity.Replacement,
    entity.Description,
    entity.AppliesToAllProfiles,
    entity.IsEndingCharacterRequired,
    entity.IsTriggerInsideWord,
    [.. entity.Profiles.Select(p => p.ProfileId)],
    [.. entity.Categories.Select(c => c.CategoryId)],
    entity.CreatedAt,
    entity.UpdatedAt,
    entity.Kind,
    entity.IsCaseSensitive,
    entity.OmitEndingCharacter);
```

`RestoreHotstringCommand.cs` and `RevertHotstringCommand.cs` — the `HotstringDefinition` built from the snapshot (Task 1 wrap) gains `snapshot.Kind, snapshot.IsCaseSensitive, snapshot.OmitEndingCharacter` as its last three args.

`GetHotstringHistoryVersionQuery.cs` (~lines 35–39): if `HotstringHistoryVersionDto` embeds the `HotstringSnapshot` record itself → nothing to do; if it copies individual fields → append the three new ones the same way.

- [ ] **Step 6: Write failing round-trip integration tests** — `tests/AHKFlowApp.Application.Tests/History/HotstringNewFieldHistoryTests.cs` (mirrors `UpdateCaptureTests.cs`; if a handler ctor differs, copy the exact arrange from `UpdateCaptureTests.cs` / `DeleteHotstringCommandHandlerTests.cs`):

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class HotstringNewFieldHistoryTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task RevertHotstring_RestoresCaseSensitiveAndOmitFlags()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("flags1").WithReplacement("x")
            .WithCaseSensitive(true).WithOmitEndingCharacter(true).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Update turns both flags off — the before-image snapshot must carry them.
        await using (AppDbContext db = fx.CreateContext())
        {
            UpdateHotstringCommandHandler update = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));
            Result<HotstringDto> updated = await update.ExecuteAsync(
                new UpdateHotstringCommand(entity.Id,
                    new UpdateHotstringDto("flags1", "x", null, true, true, true, null)), default);
            updated.IsSuccess.Should().BeTrue();
            updated.Value.IsCaseSensitive.Should().BeFalse();
        }

        await using AppDbContext revertDb = fx.CreateContext();
        RevertHotstringCommandHandler revert = new(
            revertDb, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(revertDb, TimeProvider.System));
        Result<HotstringDto> result = await revert.ExecuteAsync(
            new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Kind.Should().Be(HotstringKind.Text);
        result.Value.IsCaseSensitive.Should().BeTrue();
        result.Value.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public async Task RestoreHotstring_AfterDelete_RehydratesNewFlags()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("flags2").WithReplacement("x")
            .WithCaseSensitive(true).WithOmitEndingCharacter(true).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Delete via the real handler so the tombstone snapshot is written the production way.
        // (Copy handler construction from DeleteHotstringCommandHandlerTests.cs if the ctor differs.)
        await using (AppDbContext db = fx.CreateContext())
        {
            DeleteHotstringCommandHandler delete = new(
                db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
            (await delete.ExecuteAsync(new DeleteHotstringCommand(entity.Id), default))
                .IsSuccess.Should().BeTrue();
        }

        await using AppDbContext restoreDb = fx.CreateContext();
        RestoreHotstringCommandHandler restore = new(
            restoreDb, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(restoreDb, TimeProvider.System));
        Result<HotstringDto> result = await restore.ExecuteAsync(
            new RestoreHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.IsCaseSensitive.Should().BeTrue();
        result.Value.OmitEndingCharacter.Should().BeTrue();
    }
}
```

- [ ] **Step 7: Run** — `dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --filter "FullyQualifiedName~HotstringNewFieldHistoryTests"` → PASS (fix handler ctor args per existing tests if compile differs). Then the whole History folder: `--filter "FullyQualifiedName~History"` → PASS.
- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: round-trip kind + option flags through history snapshots"
```

---

### Task 6: CLI — Kind in DTO + table column

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Services/IHotstringsApiClient.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Output/HotstringTableFormatter.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Output/HotstringTableFormatterTests.cs`, `tests/AHKFlowApp.CLI.Tests/Integration/HotstringCliIntegrationTests.cs`

**Interfaces:**
- Produces: CLI-local `HotstringKind` enum (same values) + `HotstringDto` gains the trailing trio. Table layout: `Trigger(20) Kind(8) Replacement(40) Profiles(24) Updated(19)`.
- Per spec D6: CLI is display-only — `CreateHotstringDto` and `ahkflow hotstring new` flags unchanged.

- [ ] **Step 1: Write failing formatter test** — append to `HotstringTableFormatterTests.cs`:

```csharp
[Fact]
public void Write_RendersKindColumn()
{
    StringWriter sw = new();
    PagedList<HotstringDto> page = new([Hotstring()], 1, 50, 1);

    HotstringTableFormatter.Write(sw, page, new Dictionary<Guid, string>());

    sw.ToString().Should().Contain("Kind");
    sw.ToString().Should().Contain("Text");
}
```

(`Hotstring()` is the file's existing local factory helper — its optional-parameter call sites survive the trailing DTO additions.)

- [ ] **Step 2: Verify red** — `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~HotstringTableFormatterTests"` → FAIL (no Kind column).

- [ ] **Step 3: Extend CLI DTOs** — in `IHotstringsApiClient.cs`, add the enum and extend the read DTO:

```csharp
public enum HotstringKind
{
    Text = 0,
    DateTime = 1,
    Macro = 2,
    Script = 3,
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
    DateTimeOffset UpdatedAt,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);
```

(`CreateHotstringDto` unchanged.)

- [ ] **Step 4: Add the Kind column** to `HotstringTableFormatter.cs` — new const `private const int KindWidth = 8;`, insert a Kind segment right after Trigger in the header, the dashes row, and the data row, plus a label helper:

```csharp
writer.WriteLine(string.Join("  ",
    Pad("Trigger", TriggerWidth),
    Pad("Kind", KindWidth),
    Pad("Replacement", ReplacementWidth),
    Pad("Profiles", ProfilesWidth),
    Pad("Updated", UpdatedWidth)));
writer.WriteLine(string.Join("  ",
    new string('-', TriggerWidth),
    new string('-', KindWidth),
    new string('-', ReplacementWidth),
    new string('-', ProfilesWidth),
    new string('-', UpdatedWidth)));

// per-row (inside the foreach):
writer.WriteLine(string.Join("  ",
    Pad(Truncate(dto.Trigger, TriggerWidth), TriggerWidth),
    Pad(KindLabel(dto.Kind), KindWidth),
    Pad(Truncate(dto.Replacement, ReplacementWidth), ReplacementWidth),
    Pad(Truncate(FormatProfiles(dto, profileNamesById), ProfilesWidth), ProfilesWidth),
    updated));

private static string KindLabel(HotstringKind kind) => kind switch
{
    HotstringKind.Text => "Text",
    HotstringKind.DateTime => "DateTime",
    HotstringKind.Macro => "Macro",
    HotstringKind.Script => "Script",
    _ => kind.ToString(),
};
```

- [ ] **Step 5: Verify green** — re-run Step 2 filter → PASS. Fix any existing formatter tests that assert exact full-line strings (insert the Kind cell).
- [ ] **Step 6: Extend integration assertion** — in `HotstringCliIntegrationTests.List_HappyPath_RendersSeededTriggers`, add `stdout.Should().Contain("Kind");`. Run `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release` → PASS (Docker needed).
- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: CLI kind column"
```

---

### Task 7: UI foundation — mirrored DTOs, edit model, dialog Options panel, mobile list

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringKind.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringDto.cs`, `CreateHotstringDto.cs`, `UpdateHotstringDto.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringEditDialog.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringMobileList.razor`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Validation/HotstringEditModelTests.cs`, `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringEditDialogTests.cs`

**Interfaces:**
- Produces (Task 8 consumes): `HotstringEditModel` gains `HotstringKind Kind` (default Text), `bool IsCaseSensitive`, `bool OmitEndingCharacter`, and computed `bool ExpandImmediately` (inverse of `IsEndingCharacterRequired`). UI `HotstringDto` gains the same trailing trio as the server DTO.
- Dialog checkbox labels (spec §6, exact copy): **Case sensitive**, **Expand immediately (no ending character)**, **Trigger inside words**, **Omit ending character**. `data-test` hooks: `case-sensitive-checkbox`, `expand-immediately-checkbox`, `inside-words-checkbox`, `omit-ending-checkbox`.

- [ ] **Step 1: Write failing edit-model tests** — append to `HotstringEditModelTests.cs`:

```csharp
[Fact]
public void ExpandImmediately_InvertsEndingCharacterRequired()
{
    HotstringEditModel model = new() { IsEndingCharacterRequired = true };

    model.ExpandImmediately.Should().BeFalse();

    model.ExpandImmediately = true;
    model.IsEndingCharacterRequired.Should().BeFalse();
}

[Fact]
public void ToCreateDto_ThreadsKindAndNewFlags()
{
    HotstringEditModel model = new()
    {
        Trigger = "btw",
        Replacement = "x",
        IsCaseSensitive = true,
        OmitEndingCharacter = true,
    };

    CreateHotstringDto dto = model.ToCreateDto();

    dto.Kind.Should().Be(HotstringKind.Text);
    dto.IsCaseSensitive.Should().BeTrue();
    dto.OmitEndingCharacter.Should().BeTrue();
}

[Fact]
public void FromDto_AndClone_PreserveNewFields()
{
    HotstringDto dto = new(Guid.NewGuid(), [], true, "btw", "x", null, true, false,
        DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
        HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true);

    HotstringEditModel clone = HotstringEditModel.FromDto(dto).Clone();

    clone.IsCaseSensitive.Should().BeTrue();
    clone.OmitEndingCharacter.Should().BeTrue();
}
```

- [ ] **Step 2: Verify red** — `dotnet build` → compile errors.

- [ ] **Step 3: Mirror the enum + extend UI DTOs.**

`src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringKind.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public enum HotstringKind
{
    Text = 0,
    DateTime = 1,
    Macro = 2,
    Script = 3,
}
```

Extend all three UI DTO records with the identical trailing trio used server-side (Task 4 Step 3 shapes — `HotstringDto` after `CategoryIds`, `CreateHotstringDto`/`UpdateHotstringDto` after `CategoryIds`): `HotstringKind Kind = HotstringKind.Text, bool IsCaseSensitive = false, bool OmitEndingCharacter = false`.

- [ ] **Step 4: Extend `HotstringEditModel`** — new members + threading:

```csharp
public HotstringKind Kind { get; set; } = HotstringKind.Text;
public bool IsCaseSensitive { get; set; }
public bool OmitEndingCharacter { get; set; }

/// <summary>UI-facing inverse of <see cref="IsEndingCharacterRequired"/> (spec label “Expand immediately”).</summary>
public bool ExpandImmediately
{
    get => !IsEndingCharacterRequired;
    set => IsEndingCharacterRequired = !value;
}
```

Thread `Kind`, `IsCaseSensitive`, `OmitEndingCharacter` through all four existing members: `FromDto` (from `dto.*`), `Clone`, `ToCreateDto`, `ToUpdateDto` (append as the last three args, after the `CategoryIds` collection expression).

- [ ] **Step 5: Verify green** — `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringEditModelTests"` → PASS.

- [ ] **Step 6: Dialog Options panel.** Verify `MudCheckBox` params via `mcp__mudblazor__get_component_parameters` first. In `HotstringEditDialog.razor`, replace the two existing option checkboxes (lines 39–40: "Ending character required", "Trigger inside word") with:

```razor
<MudText Typo="Typo.subtitle2" Class="mt-1">Trigger options</MudText>
<MudCheckBox T="bool" @bind-Value="Item.IsCaseSensitive" Label="Case sensitive"
             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "case-sensitive-checkbox" })" />
<MudCheckBox T="bool" @bind-Value="Item.ExpandImmediately" Label="Expand immediately (no ending character)"
             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "expand-immediately-checkbox" })" />
<MudCheckBox T="bool" @bind-Value="Item.IsTriggerInsideWord" Label="Trigger inside words"
             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "inside-words-checkbox" })" />
<MudCheckBox T="bool" @bind-Value="Item.OmitEndingCharacter" Label="Omit ending character"
             Disabled="@Item.ExpandImmediately"
             UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "omit-ending-checkbox" })" />
```

(No kind selector — hidden until Phase 2, spec D4. `Omit ending character` disabled while `Expand immediately` is on because the emitter suppresses `O` under `*`.)

- [ ] **Step 7: Mobile expanded panel** — in `HotstringMobileList.razor` (lines ~66–69) extend the options line:

```razor
<MudText Typo="Typo.body2">
    <strong>End-char:</strong> @(item.IsEndingCharacterRequired ? "✓" : "✗") &nbsp;
    <strong>In-word:</strong> @(item.IsTriggerInsideWord ? "✓" : "✗") &nbsp;
    <strong>Case:</strong> @(item.IsCaseSensitive ? "✓" : "✗") &nbsp;
    <strong>Omit end-char:</strong> @(item.OmitEndingCharacter ? "✓" : "✗")
</MudText>
```

- [ ] **Step 7a: Mobile expanded-row test** — append to `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringMobileListTests.cs` (same expand pattern as `EditButton_RaisesOnEdit`):

```csharp
[Fact]
public async Task ExpandedRow_ShowsCaseAndOmitEndingCharacterFlags()
{
    HotstringEditModel item = Item();
    item.IsCaseSensitive = true;
    item.OmitEndingCharacter = true;

    IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
        .Add(c => c.Items, [item])
        .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
        .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

    await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

    cut.WaitForAssertion(() =>
    {
        cut.Markup.Should().Contain("Case:");
        cut.Markup.Should().Contain("Omit end-char:");
    });
}
```

- [ ] **Step 8: Write dialog bUnit test** — append to `HotstringEditDialogTests.cs` (same arrange as the file's `SaveInCreateMode_CallsCreateAsync`):

```csharp
[Fact]
public async Task SaveInCreateMode_WithCaseSensitiveChecked_SendsNewFlags()
{
    HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
        DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
    _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
        .Returns(ApiResult<HotstringDto>.Ok(created));

    Render<MudPopoverProvider>();
    IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

    await provider.InvokeAsync(async () =>
    {
        IDialogService dialogService = Services.GetRequiredService<IDialogService>();
        await dialogService.ShowAsync<HotstringEditDialog>("New",
            new DialogParameters
            {
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            },
            new DialogOptions { FullScreen = true, CloseButton = false });
    });

    provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
    provider.Find("input[data-test=\"trigger-input\"]").Change("btw");
    provider.Find("textarea[data-test=\"replacement-input\"]").Change("by the way");
    provider.Find("input[data-test=\"case-sensitive-checkbox\"]").Change(true);
    provider.Find("input[data-test=\"omit-ending-checkbox\"]").Change(true);
    provider.Find("button.commit-edit").Click();

    provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
        Arg.Is<CreateHotstringDto>(d => d.IsCaseSensitive && d.OmitEndingCharacter),
        Arg.Any<CancellationToken>()));
}
```

- [ ] **Step 9: Run** — `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release` → PASS (fix any test that asserted the old checkbox labels).
- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: dialog trigger-options panel + UI kind/flag mirrors"
```

---

### Task 8: Desktop grid — Type/Options badge column + "Edit details"

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor.css`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/HotstringsPageTests.cs`

**Interfaces:**
- Consumes: `HotstringEditModel.Kind/IsCaseSensitive/OmitEndingCharacter` (Task 7).
- Test hooks produced: `.type-badge`, `.option-glyphs` (cell), `button.edit-details` (action).

- [ ] **Step 1: Write failing page tests** — append to `HotstringsPageTests.cs`:

```csharp
[Fact]
public Task Page_RendersTypeBadgeWithOptionGlyphs()
{
    var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
        false, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
        HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: false);
    StubList(Page(dto));

    IRenderedComponent<Hotstrings> cut = RenderPage();

    cut.WaitForAssertion(() =>
    {
        cut.Find(".type-badge").TextContent.Should().Contain("Text");
        cut.Find(".option-glyphs").TextContent.Should().Be("*?C");
    });
    return Task.CompletedTask;
}

[Fact]
public Task Page_OmitEndingCharacter_SuppressedWhenExpandImmediately()
{
    // OmitEndingCharacter can be true alongside IsEndingCharacterRequired=false (the dialog only
    // disables the checkbox, it doesn't clear the value) — the badge must hide "O" here exactly
    // like the emitter suppresses the O option under *.
    var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
        false, false, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
        HotstringKind.Text, IsCaseSensitive: false, OmitEndingCharacter: true);
    StubList(Page(dto));

    IRenderedComponent<Hotstrings> cut = RenderPage();

    cut.WaitForAssertion(() =>
        cut.Find(".option-glyphs").TextContent.Should().Be("*"));
    return Task.CompletedTask;
}

[Fact]
public Task Page_EditDetails_OpensDialogWithItem()
{
    // MudDialogProvider renders dialog content into its own root, not into the component that
    // called ShowAsync — so the dialog markup must be queried on `provider`, not on `cut`
    // (RenderPage() discards its MudDialogProvider reference; render it manually here instead,
    // matching the pattern in HotstringEditDialogTests.cs).
    var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
        true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
    StubList(Page(dto));

    Render<MudPopoverProvider>();
    IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
    IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

    cut.WaitForAssertion(() => cut.Find("button.edit-details"));
    cut.Find("button.edit-details").Click();

    provider.WaitForAssertion(() =>
        provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be("btw"));
    return Task.CompletedTask;
}
```

- [ ] **Step 2: Verify red** — `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release --filter "FullyQualifiedName~HotstringsPageTests"` → FAIL (selectors missing).

- [ ] **Step 3: Replace the two checkbox columns** (lines 131–154, `IsEndingCharacterRequired` + `IsTriggerInsideWord` PropertyColumns) with one badge column. Verify `MudChip`/`MudTooltip` params via `mcp__mudblazor__get_component_parameters` first:

```razor
<TemplateColumn Title="Type" Sortable="false" Filterable="false">
    <CellTemplate>
        <MudTooltip Text="@OptionsTooltip(context.Item)">
            <span class="type-badge">
                <MudChip T="string" Size="Size.Small" Color="Color.Default">@KindLabel(context.Item.Kind)</MudChip>
                <span class="option-glyphs">@OptionGlyphs(context.Item)</span>
            </span>
        </MudTooltip>
    </CellTemplate>
</TemplateColumn>
```

(Sortable stays `false` in Phase 1 — server-side Kind sort arrives with the Phase 2 list-query change.)

`@code` helpers:

```csharp
private static string KindLabel(HotstringKind kind) => kind switch
{
    HotstringKind.Text => "Text",
    HotstringKind.DateTime => "Date & time",
    HotstringKind.Macro => "Macro",
    HotstringKind.Script => "Script",
    _ => kind.ToString(),
};

private static string OptionGlyphs(HotstringEditModel item)
{
    string glyphs = "";
    if (!item.IsEndingCharacterRequired) glyphs += "*";
    if (item.IsTriggerInsideWord) glyphs += "?";
    if (item.IsCaseSensitive) glyphs += "C";
    if (item.OmitEndingCharacter && item.IsEndingCharacterRequired) glyphs += "O"; // O is meaningless (and suppressed by the emitter) under *
    return glyphs;
}

private static string OptionsTooltip(HotstringEditModel item)
{
    List<string> parts = [KindLabel(item.Kind)];
    if (!item.IsEndingCharacterRequired) parts.Add("Expands immediately (no ending character)");
    if (item.IsTriggerInsideWord) parts.Add("Triggers inside words");
    if (item.IsCaseSensitive) parts.Add("Case sensitive");
    if (item.OmitEndingCharacter && item.IsEndingCharacterRequired) parts.Add("Omits ending character");
    return string.Join(" · ", parts);
}
```

> The dialog disables the "Omit ending character" checkbox while "Expand immediately" is on (Task 7 Step 6), but a user can still reach `OmitEndingCharacter=true, IsEndingCharacterRequired=false` by checking Omit first, then Expand immediately — the checkbox just becomes disabled, its bound value doesn't reset. So this state is real and both helpers above must gate on it, matching the emitter's own `O` suppression (Task 3 Step 3).

- [ ] **Step 4: "Edit details" action + desktop dialog options.** In `RenderActions` (line 823), add as the **first** button of the non-editing branch:

```razor
<MudIconButton Class="edit-details" Icon="@Icons.Material.Filled.EditNote"
               OnClick="() => OpenEditDetailsDialogAsync(item)" />
```

Refactor the dialog openers — the existing `OpenEditDialogAsync` body (lines ~692–722) becomes the shared core taking a `DialogOptions` parameter:

```csharp
private Task OpenEditDialogAsync(HotstringEditModel item) =>
    OpenEditDialogCoreAsync(item, new DialogOptions { FullScreen = true, CloseButton = false });

private Task OpenEditDetailsDialogAsync(HotstringEditModel item) =>
    OpenEditDialogCoreAsync(item, new DialogOptions { FullScreen = false, MaxWidth = MaxWidth.Medium, CloseButton = false });

private async Task OpenEditDialogCoreAsync(HotstringEditModel item, DialogOptions options)
{
    if (_dialogOpen) return;
    _dialogOpen = true;
    try
    {
        DialogParameters parameters = new()
        {
            [nameof(HotstringEditDialog.Item)] = item.Clone(),
            [nameof(HotstringEditDialog.Profiles)] = _profiles,
            [nameof(HotstringEditDialog.Categories)] = _categories,
        };

        IDialogReference dialog = await DialogService.ShowAsync<HotstringEditDialog>(
            "Edit hotstring", parameters, options);

        DialogResult? result = await dialog.Result;
        if (result?.Canceled == false)
        {
            Snackbar.Add("Hotstring updated.", Severity.Success);
            await ReloadAllAsync();
        }
    }
    finally { _dialogOpen = false; }
}
```

(Keep the exact snackbar text and reload call currently in `OpenEditDialogAsync` — if the current body differs from the above in wording, the current body wins; only the `options` argument is new.)

- [ ] **Step 5: Clean up dead sort branches** — in `GetSort` (lines ~359–376) remove the `"isEndingCharacterRequired"` and `"isTriggerInsideWord"` arms (columns no longer exist; the API keeps accepting the params for compat).

- [ ] **Step 6: Renumber the CSS.** In `Hotstrings.razor.css`, replace the nth-child blocks 6–9 (lines 81–97): old 6+7 (two 72px checkbox columns) become one badge column; categories/actions shift down one; actions widened for the 4th icon:

```css
::deep .hotstrings-grid th:nth-child(6),
::deep .hotstrings-grid td:nth-child(6) {
    width: 130px;
    text-align: center;
}

::deep .hotstrings-grid th:nth-child(7),
::deep .hotstrings-grid td:nth-child(7) {
    width: 10%;
}

::deep .hotstrings-grid th:nth-child(8),
::deep .hotstrings-grid td:nth-child(8) {
    width: 132px;
}

::deep .hotstrings-grid .option-glyphs {
    opacity: 0.6;
    font-family: monospace;
    margin-left: 4px;
}
```

Also update the Actions `TemplateColumn` `HeaderStyle` from `width:160px` accordingly (keep 160px — 4 icons fit).

- [ ] **Step 7: Verify green** — Step 2 filter → PASS. Then the whole project: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --configuration Release` → PASS. Fix any existing page test that referenced the removed checkbox columns (`grep -n "Ending char required\|Trigger inside word" tests/AHKFlowApp.UI.Blazor.Tests -r`).
- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: grid type/options badge column + edit-details dialog"
```

---

### Task 9: Changelog + full verification

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Changelog entry** — under `## [Unreleased]`:

```markdown
### Added

- Hotstring option toggles: case sensitive and omit ending character.
- Type/Options badge column in the hotstrings grid (replaces the two option checkbox columns).
- "Edit details" dialog for hotstrings on desktop.
- `ahkflow hotstring list` shows a Kind column.

### Changed

- Generated scripts always emit the `T` (literal text) option for text hotstrings, so replacements are inserted exactly as typed.
```

- [ ] **Step 2: Full solution gate** — `dotnet build --configuration Release` then `dotnet test --configuration Release --no-build --verbosity normal` (Docker running) → all green.
- [ ] **Step 3: Invoke the `dck-verify` skill** (per spec §9: every phase ends with dck-verify).
- [ ] **Step 4: End-to-end smoke** (spec §11): run API (`dotnet run --project src/Backend/AHKFlowApp.API --launch-profile "Docker SQL (Recommended)"`) + Blazor (`dotnet run --project src/Frontend/AHKFlowApp.UI.Blazor`); via the `playwright-cli` skill: create a hotstring, open Edit details, enable Case sensitive + Omit ending character, save; verify the badge shows `C O` glyphs; verify inline edit of Trigger/Replacement still works; download the profile script and confirm the line reads `:COT:trigger::replacement` and a default hotstring reads `:T:trigger::replacement`.
- [ ] **Step 5: Commit + finish**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for hotstring option toggles"
```

Then use **superpowers:finishing-a-development-branch** (PR to `main` via `gh`, per GitHub Flow).

---

## Verification summary

- **Per task:** the test commands embedded in each task's steps (validators/emitter/domain = unit; handlers/history/API/CLI = Testcontainers integration, Docker required; UI = bUnit).
- **Golden truth:** `AhkScriptGeneratorTests` options Theory asserts exact emitted lines incl. order `* ? C O T` and O-suppression; `AhkScriptGeneratorIntegrationTests` asserts a byte-exact full script; `AhkHotstringRoundTripTests` proves emit→parse→emit is stable with always-`T`.
- **Back-compat proof:** `HotstringSnapshotCompatibilityTests` (legacy JSON → Text defaults), `HotstringNewFieldHistoryTests` (post-migration revert/restore round-trips flags), API tests (old-shape POST bodies still work — defaults), CLI formatter helper unchanged (trailing defaults).
- **End-to-end:** Task 9 Step 4.

## Unresolved questions

None — parser bare-`T` acceptance and desktop "Edit details" in Phase 1 were resolved with you during planning.
