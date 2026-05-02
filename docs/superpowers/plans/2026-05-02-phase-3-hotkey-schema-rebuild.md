# Phase 3: Hotkey Schema Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `Hotkey` aggregate from the free-form `Trigger`/`Action`/`Description` strings + nullable `ProfileId` to the AHKFlow target schema (`Description`, `Key`, `Ctrl`/`Alt`/`Shift`/`Win` flags, `HotkeyAction` enum, `Parameters`, `AppliesToAllProfiles`) with a `HotkeyProfile` junction table, and rebuild the API + frontend on top of it.

**Architecture:** Domain gets a new `HotkeyAction` enum, a `HotkeyProfile` junction entity, and a fully reshaped `Hotkey` entity with structured fields. Infrastructure adds EF configurations for both, plus a destructive migration that drops the old columns and indexes (dev-only per spec D7). Application DTOs/validators/handlers/queries are rebuilt to surface the new shape; junction rows mirror the Phase 2 hotstring pattern. UI: replace the placeholder `Hotkeys.razor` with an inline-edit MudTable (Description, Key, 4 modifier checkboxes, Action select, Profile multi-select + "Any", Parameters). Hotstring is NOT touched in this phase.

**Tech Stack:** .NET 10, EF Core 10 (SQL Server), MediatR + Ardalis.Result, FluentValidation, Blazor WebAssembly (MudBlazor 9.x), xUnit + FluentAssertions + Testcontainers + bUnit.

**Maps to backlog:** 022 (replace) + 022b.
**Spec:** `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 3).

---

## Branch Setup

Phase 3 depends on the `Profile` entity (Phase 1) AND the `HotstringProfile` junction precedent (Phase 2: gives us `Profiles` on `IAppDbContext`, established M2M+`AppliesToAllProfiles` pattern):

```bash
git checkout feature/024b-many-to-many-profile-association
git checkout -b feature/022b-hotkey-schema-rebuild
```

---

## File Map

| Action | File |
|--------|------|
| Create | `src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs` |
| Create | `src/Backend/AHKFlowApp.Domain/Entities/HotkeyProfile.cs` |
| Modify | `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` (full rewrite) |
| Create | `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyProfileConfiguration.cs` |
| Modify | `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs` |
| Modify | `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` |
| Create | `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_Phase3HotkeyRebuild.cs` (generated) |
| Modify | `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Mapping/HotkeyMappings.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs` (full rewrite) |
| Modify | `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyQuery.cs` (small) |
| Modify | `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` (full rewrite) |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/CreateHotkeyCommandValidatorTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/UpdateHotkeyCommandValidatorTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/CreateHotkeyCommandHandlerTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/UpdateHotkeyCommandHandlerTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/GetHotkeyQueryHandlerTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/ListHotkeysQueryHandlerTests.cs` |
| Create | `tests/AHKFlowApp.Application.Tests/Hotkeys/DeleteHotkeyCommandHandlerTests.cs` |
| Modify | `tests/AHKFlowApp.API.Tests/Hotkeys/HotkeysEndpointsTests.cs` (full rewrite) |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyDto.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotkeyDto.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotkeyDto.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeysApiClient.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotkeysApiClient.cs` |
| Create | `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotkeyEditModel.cs` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` (replace stub) |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` (register `IHotkeysApiClient`) |
| Create | `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs` |

> **UI density note (CLAUDE.md says inline edit ≤6 fields):** the spec dictates the row layout (~10 columns). Inline edit wins — keep it tight, reuse the `overflow-x: auto` scroll wrapper from `Hotstrings.razor`. No dialog.

---

## Task 1: Domain — `HotkeyAction` enum

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs`

- [ ] **Step 1: Create the enum**

```csharp
namespace AHKFlowApp.Domain.Enums;

public enum HotkeyAction
{
    Send = 0,
    Run = 1,
}
```

- [ ] **Step 2: Verify it compiles**

```bash
dotnet build src/Backend/AHKFlowApp.Domain --configuration Release
```

Expected: `Build succeeded.`

---

## Task 2: Domain — `HotkeyProfile` junction entity

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Entities/HotkeyProfile.cs`

- [ ] **Step 1: Create the junction entity**

```csharp
namespace AHKFlowApp.Domain.Entities;

public sealed class HotkeyProfile
{
    private HotkeyProfile() { }

    public Guid HotkeyId { get; private set; }
    public Guid ProfileId { get; private set; }

    public static HotkeyProfile Create(Guid hotkeyId, Guid profileId) =>
        new() { HotkeyId = hotkeyId, ProfileId = profileId };
}
```

- [ ] **Step 2: Verify it compiles**

```bash
dotnet build src/Backend/AHKFlowApp.Domain --configuration Release
```

Expected: `Build succeeded.`

---

## Task 3: Domain — Rebuild `Hotkey` entity

**Files:**
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs`

- [ ] **Step 1: Replace the file content**

Replace the entire content of `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class Hotkey
{
    private Hotkey()
    {
        Description = string.Empty;
        Key = string.Empty;
        Parameters = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Description { get; private set; }
    public string Key { get; private set; }
    public bool Ctrl { get; private set; }
    public bool Alt { get; private set; }
    public bool Shift { get; private set; }
    public bool Win { get; private set; }
    public HotkeyAction Action { get; private set; }
    public string Parameters { get; private set; }
    public bool AppliesToAllProfiles { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotkeyProfile> Profiles { get; private set; } = [];

    public static Hotkey Create(
        Guid ownerOid,
        string description,
        string key,
        bool ctrl,
        bool alt,
        bool shift,
        bool win,
        HotkeyAction action,
        string parameters,
        bool appliesToAllProfiles,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Hotkey
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Description = description,
            Key = key,
            Ctrl = ctrl,
            Alt = alt,
            Shift = shift,
            Win = win,
            Action = action,
            Parameters = parameters,
            AppliesToAllProfiles = appliesToAllProfiles,
            CreatedAt = now,
            UpdatedAt = now,
        };
    }

    public void Update(
        string description,
        string key,
        bool ctrl,
        bool alt,
        bool shift,
        bool win,
        HotkeyAction action,
        string parameters,
        bool appliesToAllProfiles,
        TimeProvider clock)
    {
        Description = description;
        Key = key;
        Ctrl = ctrl;
        Alt = alt;
        Shift = shift;
        Win = win;
        Action = action;
        Parameters = parameters;
        AppliesToAllProfiles = appliesToAllProfiles;
        UpdatedAt = clock.GetUtcNow();
    }
}
```

- [ ] **Step 2: Build domain (downstream projects will fail — expected)**

```bash
dotnet build src/Backend/AHKFlowApp.Domain --configuration Release
```

Expected: `Build succeeded.` for Domain itself.

---

## Task 4: Test utilities — Rewrite `HotkeyBuilder`

**Files:**
- Modify: `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`

- [ ] **Step 1: Replace the file content**

Replace the entire content of `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HotkeyBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _description = "Open Notepad";
    private string _key = "n";
    private bool _ctrl;
    private bool _alt;
    private bool _shift;
    private bool _win;
    private HotkeyAction _action = HotkeyAction.Run;
    private string _parameters = "notepad.exe";
    private bool _appliesToAllProfiles = true;
    private TimeProvider _clock = TimeProvider.System;

    public HotkeyBuilder WithOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }
    public HotkeyBuilder WithDescription(string description) { _description = description; return this; }
    public HotkeyBuilder WithKey(string key) { _key = key; return this; }
    public HotkeyBuilder WithCtrl(bool value = true) { _ctrl = value; return this; }
    public HotkeyBuilder WithAlt(bool value = true) { _alt = value; return this; }
    public HotkeyBuilder WithShift(bool value = true) { _shift = value; return this; }
    public HotkeyBuilder WithWin(bool value = true) { _win = value; return this; }
    public HotkeyBuilder WithAction(HotkeyAction action) { _action = action; return this; }
    public HotkeyBuilder WithParameters(string parameters) { _parameters = parameters; return this; }
    public HotkeyBuilder AppliesToAll(bool value = true) { _appliesToAllProfiles = value; return this; }
    public HotkeyBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public Hotkey Build() => Hotkey.Create(
        _ownerOid, _description, _key, _ctrl, _alt, _shift, _win,
        _action, _parameters, _appliesToAllProfiles, _clock);
}
```

---

## Task 5: Infrastructure — EF configurations + DbContext

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyProfileConfiguration.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`

- [ ] **Step 1: Create `HotkeyProfileConfiguration`**

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotkeyProfileConfiguration : IEntityTypeConfiguration<HotkeyProfile>
{
    public void Configure(EntityTypeBuilder<HotkeyProfile> builder)
    {
        builder.HasKey(x => new { x.HotkeyId, x.ProfileId });

        builder.HasOne<Hotkey>()
            .WithMany(h => h.Profiles)
            .HasForeignKey(x => x.HotkeyId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne<Profile>()
            .WithMany()
            .HasForeignKey(x => x.ProfileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
```

- [ ] **Step 2: Replace `HotkeyConfiguration`**

Replace the entire content of `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotkeyConfiguration : IEntityTypeConfiguration<Hotkey>
{
    public void Configure(EntityTypeBuilder<Hotkey> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.Description)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(x => x.Key)
            .IsRequired()
            .HasMaxLength(20);

        builder.Property(x => x.Ctrl).IsRequired();
        builder.Property(x => x.Alt).IsRequired();
        builder.Property(x => x.Shift).IsRequired();
        builder.Property(x => x.Win).IsRequired();

        // Persist enum as int (default for EF, made explicit here for clarity).
        builder.Property(x => x.Action)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(x => x.Parameters)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One mapping per modifier-combo per user.
        builder.HasIndex(x => new { x.OwnerOid, x.Key, x.Ctrl, x.Alt, x.Shift, x.Win })
            .IsUnique()
            .HasDatabaseName("IX_Hotkey_Owner_Modifiers");
    }
}
```

- [ ] **Step 3: Update `IAppDbContext`**

Replace the entire content of `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<Hotstring> Hotstrings { get; }
    DbSet<HotstringProfile> HotstringProfiles { get; }
    DbSet<Hotkey> Hotkeys { get; }
    DbSet<HotkeyProfile> HotkeyProfiles { get; }
    DbSet<Profile> Profiles { get; }
    DbSet<UserPreference> UserPreferences { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);

    Microsoft.EntityFrameworkCore.ChangeTracking.EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class;
}
```

> **Note:** the `Entry<TEntity>` accessor is already on the interface from Phase 2 (used by `CreateHotstringCommandHandler` to load junction rows). If your branch lacks it, add it; if it's already there, just keep the line.

- [ ] **Step 4: Update `AppDbContext`**

In `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`, ensure both new DbSets exist alongside the Phase 2 set. The full body should read:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<TestMessage> TestMessages => Set<TestMessage>();
    public DbSet<Hotstring> Hotstrings => Set<Hotstring>();
    public DbSet<HotstringProfile> HotstringProfiles => Set<HotstringProfile>();
    public DbSet<Hotkey> Hotkeys => Set<Hotkey>();
    public DbSet<HotkeyProfile> HotkeyProfiles => Set<HotkeyProfile>();
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<UserPreference> UserPreferences => Set<UserPreference>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
```

- [ ] **Step 5: Build Infrastructure (Application layer will still fail — expected)**

```bash
dotnet build src/Backend/AHKFlowApp.Infrastructure --configuration Release
```

Expected: Application layer build errors only (DTOs/handlers still reference old fields). Infrastructure itself compiles.

---

## Task 6: EF Core Migration

**Files:**
- Create: generated migration under `src/Backend/AHKFlowApp.Infrastructure/Migrations/`

- [ ] **Step 1: Add the migration**

```bash
dotnet ef migrations add Phase3HotkeyRebuild --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Expected: New migration file `<timestamp>_Phase3HotkeyRebuild.cs` is created.

- [ ] **Step 2: Verify the generated migration shape (CRITICAL)**

Open the generated `<timestamp>_Phase3HotkeyRebuild.cs` and confirm `Up()` does ALL of the following:

**Drop:**
- Drop index `IX_Hotkey_Owner_Profile_Trigger`
- Drop index `IX_Hotkey_Owner_Trigger_NoProfile`
- Drop column `ProfileId` on `Hotkeys`
- Drop column `Trigger` on `Hotkeys`
- Drop column `Description` on `Hotkeys` (will be re-added with non-null + new max length)
- Drop column `Action` on `Hotkeys` ← **must be `DropColumn`, not `AlterColumn`**. EF may emit `AlterColumn<string>` because the property name is reused. If so, edit the migration to drop and re-add.

**Add:**
- Add column `Description` (nvarchar(200), not null, default `""`)
- Add column `Key` (nvarchar(20), not null, default `""`)
- Add column `Ctrl` (bit, not null, default `0`)
- Add column `Alt` (bit, not null, default `0`)
- Add column `Shift` (bit, not null, default `0`)
- Add column `Win` (bit, not null, default `0`)
- Add column `Action` (int, not null, default `0`)
- Add column `Parameters` (nvarchar(4000), not null, default `""`)
- Add column `AppliesToAllProfiles` (bit, not null, default `0`)

**Create table + index:**
- Create table `HotkeyProfile` with columns `HotkeyId` (uniqueidentifier), `ProfileId` (uniqueidentifier)
- Composite PK `PK_HotkeyProfile (HotkeyId, ProfileId)`
- FK `FK_HotkeyProfile_Hotkeys_HotkeyId` (cascade delete)
- FK `FK_HotkeyProfile_Profiles_ProfileId` (cascade delete)
- Unique index `IX_Hotkey_Owner_Modifiers` on `(OwnerOid, Key, Ctrl, Alt, Shift, Win)`

If the migration emits `AlterColumn` for `Action` (column type change from `nvarchar` to `int`), manually edit it to `migrationBuilder.DropColumn(name: "Action", table: "Hotkeys");` followed by `migrationBuilder.AddColumn<int>(name: "Action", table: "Hotkeys", type: "int", nullable: false, defaultValue: 0);`. Mirror the inverse in `Down()`.

If anything else is missing or wrong, adjust the configuration in Task 5 and regenerate (delete the migration file first).

- [ ] **Step 3: Commit domain + infra + migration**

```bash
git add src/Backend/AHKFlowApp.Domain/Enums/HotkeyAction.cs
git add src/Backend/AHKFlowApp.Domain/Entities/HotkeyProfile.cs
git add src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyProfileConfiguration.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs
git add src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs
git add src/Backend/AHKFlowApp.Infrastructure/Migrations/
git add tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs
git commit -m "feat(domain): rebuild Hotkey schema — structured fields + HotkeyProfile junction"
```

---

## Task 7: Application — DTOs

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotkeyDto.cs`

- [ ] **Step 1: Replace HotkeyDto.cs**

Replace the entire content:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

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

---

## Task 8: Application — Validation rules

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotkeyRules.cs`

- [ ] **Step 1: Replace HotkeyRules.cs**

Replace the entire content:

```csharp
using AHKFlowApp.Domain.Enums;
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotkeyRules
{
    public const int DescriptionMaxLength = 200;
    public const int KeyMaxLength = 20;
    public const int ParametersMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidDescription<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Description is required.")
          .MaximumLength(DescriptionMaxLength).WithMessage($"Description must be {DescriptionMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, string> ValidKey<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(k => !string.IsNullOrEmpty(k)).WithMessage("Key is required.")
          .MaximumLength(KeyMaxLength).WithMessage($"Key must be {KeyMaxLength} characters or fewer.")
          .Must(k => k is not null && k.Length == k.Trim().Length)
              .WithMessage("Key must not have leading or trailing whitespace.")
          .Must(k => k is not null && k.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Key must not contain line breaks or tabs.");

    public static IRuleBuilderOptions<T, string> ValidParameters<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.MaximumLength(ParametersMaxLength)
          .WithMessage($"Parameters must be {ParametersMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, HotkeyAction> ValidAction<T>(this IRuleBuilderInitial<T, HotkeyAction> rb) =>
        rb.IsInEnum().WithMessage("Action must be a valid HotkeyAction value.");

    public static void ValidProfileAssociation<T>(
        this AbstractValidator<T> validator,
        Func<T, bool> appliesToAll,
        Func<T, Guid[]?> profileIds)
    {
        validator.When(appliesToAll, () =>
        {
            validator.RuleFor(profileIds)
                .Must(ids => ids is null || ids.Length == 0)
                .WithMessage("ProfileIds must be empty when AppliesToAllProfiles is true.");
        });

        validator.When(x => !appliesToAll(x), () =>
        {
            validator.RuleFor(profileIds)
                .Must(ids => ids is { Length: > 0 })
                .WithMessage("At least one profile must be specified when AppliesToAllProfiles is false.");

            validator.RuleForEach(profileIds)
                .Must(id => id != Guid.Empty)
                .WithMessage("ProfileIds must not contain empty GUIDs.");
        });
    }
}
```

---

## Task 9: Application — Mappings

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Mapping/HotkeyMappings.cs`

- [ ] **Step 1: Replace HotkeyMappings.cs**

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotkeyMappings
{
    public static HotkeyDto ToDto(this Hotkey h) => new(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Description,
        h.Key,
        h.Ctrl,
        h.Alt,
        h.Shift,
        h.Win,
        h.Action,
        h.Parameters,
        h.CreatedAt,
        h.UpdatedAt);
}
```

---

## Task 10: Application — Commands (Create / Update)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/CreateHotkeyCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs`

- [ ] **Step 1: Replace CreateHotkeyCommand.cs**

```csharp
using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record CreateHotkeyCommand(CreateHotkeyDto Input) : IRequest<Result<HotkeyDto>>;

public sealed class CreateHotkeyCommandValidator : AbstractValidator<CreateHotkeyCommand>
{
    public CreateHotkeyCommandValidator()
    {
        RuleFor(x => x.Input.Description).ValidDescription();
        RuleFor(x => x.Input.Key).ValidKey();
        RuleFor(x => x.Input.Parameters).ValidParameters();
        RuleFor(x => x.Input.Action).ValidAction();
        this.ValidProfileAssociation(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class CreateHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<CreateHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> Handle(CreateHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotkeyDto input = request.Input;

        bool duplicate = await db.Hotkeys.AnyAsync(
            h => h.OwnerOid == ownerOid
              && h.Key == input.Key
              && h.Ctrl == input.Ctrl
              && h.Alt == input.Alt
              && h.Shift == input.Shift
              && h.Win == input.Win,
            ct);

        if (duplicate)
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && input.ProfileIds.Contains(p.Id), ct);
            if (validCount != input.ProfileIds.Length)
                return Result.Invalid(new ValidationError("One or more ProfileIds do not exist for this user."));
        }

        var entity = Hotkey.Create(
            ownerOid,
            input.Description,
            input.Key,
            input.Ctrl,
            input.Alt,
            input.Shift,
            input.Win,
            input.Action,
            input.Parameters,
            input.AppliesToAllProfiles,
            clock);

        db.Hotkeys.Add(entity);

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
                db.HotkeyProfiles.Add(HotkeyProfile.Create(entity.Id, pid));
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }

        await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
        return Result.Success(entity.ToDto());
    }

    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

- [ ] **Step 2: Replace UpdateHotkeyCommand.cs**

```csharp
using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record UpdateHotkeyCommand(Guid Id, UpdateHotkeyDto Input) : IRequest<Result<HotkeyDto>>;

public sealed class UpdateHotkeyCommandValidator : AbstractValidator<UpdateHotkeyCommand>
{
    public UpdateHotkeyCommandValidator()
    {
        RuleFor(x => x.Input.Description).ValidDescription();
        RuleFor(x => x.Input.Key).ValidKey();
        RuleFor(x => x.Input.Parameters).ValidParameters();
        RuleFor(x => x.Input.Action).ValidAction();
        this.ValidProfileAssociation(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class UpdateHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> Handle(UpdateHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotkeyDto input = request.Input;

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && input.ProfileIds.Contains(p.Id), ct);
            if (validCount != input.ProfileIds.Length)
                return Result.Invalid(new ValidationError("One or more ProfileIds do not exist for this user."));
        }

        entity.Update(
            input.Description,
            input.Key,
            input.Ctrl,
            input.Alt,
            input.Shift,
            input.Win,
            input.Action,
            input.Parameters,
            input.AppliesToAllProfiles,
            clock);

        // Replace junction rows
        db.HotkeyProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
            {
                var junction = HotkeyProfile.Create(entity.Id, pid);
                db.HotkeyProfiles.Add(junction);
                entity.Profiles.Add(junction);
            }
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }

        return Result.Success(entity.ToDto());
    }

    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

> **Note:** The existing `DeleteHotkeyCommand.cs` does NOT need changes — junction rows cascade-delete when the parent `Hotkey` row is removed.

---

## Task 11: Application — Queries

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyQuery.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListHotkeysQuery.cs`

- [ ] **Step 1: Replace GetHotkeyQuery.cs**

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record GetHotkeyQuery(Guid Id) : IRequest<Result<HotkeyDto>>;

internal sealed class GetHotkeyQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetHotkeyQuery, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> Handle(GetHotkeyQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .AsNoTracking()
            .Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        return entity is null
            ? Result.NotFound()
            : Result.Success(entity.ToDto());
    }
}
```

- [ ] **Step 2: Replace ListHotkeysQuery.cs**

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record ListHotkeysQuery(
    Guid? ProfileId = null,
    string? Search = null,
    bool IgnoreCase = true,
    int Page = 1,
    int PageSize = 50) : IRequest<Result<PagedList<HotkeyDto>>>;

public sealed class ListHotkeysQueryValidator : AbstractValidator<ListHotkeysQuery>
{
    public ListHotkeysQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}

internal sealed class ListHotkeysQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<ListHotkeysQuery, Result<PagedList<HotkeyDto>>>
{
    public async Task<Result<PagedList<HotkeyDto>>> Handle(ListHotkeysQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IQueryable<Hotkey> query = db.Hotkeys
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid);

        if (request.ProfileId.HasValue)
        {
            Guid pid = request.ProfileId.Value;
            query = query.Where(h =>
                h.AppliesToAllProfiles ||
                h.Profiles.Any(p => p.ProfileId == pid));
        }

        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Description, pattern) ||
                EF.Functions.Like(h.Key, pattern) ||
                EF.Functions.Like(h.Parameters, pattern));
        }

        int total = await query.CountAsync(ct);

        List<HotkeyDto> items = await query
            .Include(h => h.Profiles)
            .OrderByDescending(h => h.CreatedAt)
            .ThenBy(h => h.Id)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(h => new HotkeyDto(
                h.Id,
                h.Profiles.Select(p => p.ProfileId).ToArray(),
                h.AppliesToAllProfiles,
                h.Description,
                h.Key,
                h.Ctrl,
                h.Alt,
                h.Shift,
                h.Win,
                h.Action,
                h.Parameters,
                h.CreatedAt,
                h.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotkeyDto>(items, request.Page, request.PageSize, total));
    }
}
```

- [ ] **Step 3: Build all backend projects**

```bash
dotnet build src/Backend --configuration Release
```

Expected: `Build succeeded.` with 0 errors. If errors remain, fix them before continuing.

- [ ] **Step 4: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/
git commit -m "feat(app): rebuild Hotkey DTOs, validators, commands, queries to target schema"
```

---

## Task 12: Application — Validator tests (TDD)

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/CreateHotkeyCommandValidatorTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/UpdateHotkeyCommandValidatorTests.cs`

- [ ] **Step 1: Create CreateHotkeyCommandValidatorTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class CreateHotkeyCommandValidatorTests
{
    private readonly CreateHotkeyCommandValidator _sut = new();

    private static CreateHotkeyCommand Cmd(
        string description = "Open Notepad",
        string key = "n",
        bool ctrl = false,
        bool alt = false,
        bool shift = false,
        bool win = false,
        HotkeyAction action = HotkeyAction.Run,
        string parameters = "notepad.exe",
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true)
        => new(new CreateHotkeyDto(description, key, ctrl, alt, shift, win, action, parameters, profileIds, appliesToAllProfiles));

    [Fact]
    public void Validate_AppliesToAll_NoProfiles_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: true));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_ProfileScoped_WithOneProfile_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: false, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_AppliesToAll_WithProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: true, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ProfileIds must be empty when AppliesToAllProfiles is true.");
    }

    [Fact]
    public void Validate_ProfileScoped_NoProfiles_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: false, profileIds: null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "At least one profile must be specified when AppliesToAllProfiles is false.");
    }

    [Fact]
    public void Validate_ProfileScoped_EmptyGuidInArray_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: false, profileIds: [Guid.Empty]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ProfileIds must not contain empty GUIDs.");
    }

    [Fact]
    public void Validate_WithEmptyDescription_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(description: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Description" &&
            e.ErrorMessage == "Description is required.");
    }

    [Fact]
    public void Validate_DescriptionAt200_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(description: new string('x', 200)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_DescriptionAt201_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(description: new string('x', 201)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Description");
    }

    [Fact]
    public void Validate_WithEmptyKey_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(key: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key is required.");
    }

    [Theory]
    [InlineData(" n")]
    [InlineData("n ")]
    public void Validate_KeyWithWhitespacePadding_Fails(string key)
    {
        ValidationResult result = _sut.Validate(Cmd(key: key));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("n\nx")]
    [InlineData("n\rx")]
    [InlineData("n\tx")]
    public void Validate_KeyWithControlChar_Fails(string key)
    {
        ValidationResult result = _sut.Validate(Cmd(key: key));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key must not contain line breaks or tabs.");
    }

    [Fact]
    public void Validate_KeyAt20_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(key: new string('x', 20)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_KeyAt21_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(key: new string('x', 21)));

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_ParametersAt4000_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(parameters: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_ParametersAt4001_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(parameters: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Parameters");
    }

    [Fact]
    public void Validate_InvalidActionEnum_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(action: (HotkeyAction)99));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Action" &&
            e.ErrorMessage == "Action must be a valid HotkeyAction value.");
    }
}
```

- [ ] **Step 2: Create UpdateHotkeyCommandValidatorTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class UpdateHotkeyCommandValidatorTests
{
    private readonly UpdateHotkeyCommandValidator _sut = new();

    private static UpdateHotkeyCommand Cmd(
        string description = "Open Notepad",
        string key = "n",
        bool ctrl = false,
        bool alt = false,
        bool shift = false,
        bool win = false,
        HotkeyAction action = HotkeyAction.Run,
        string parameters = "notepad.exe",
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true)
        => new(Guid.NewGuid(),
            new UpdateHotkeyDto(description, key, ctrl, alt, shift, win, action, parameters, profileIds, appliesToAllProfiles));

    [Fact]
    public void Validate_AppliesToAll_NoProfiles_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: true));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_ProfileScoped_WithOneProfile_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: false, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_AppliesToAll_WithProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: true, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_ProfileScoped_NoProfiles_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: false, profileIds: null));

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_WithEmptyDescription_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(description: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Description");
    }

    [Fact]
    public void Validate_WithEmptyKey_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(key: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Key");
    }

    [Fact]
    public void Validate_InvalidActionEnum_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(action: (HotkeyAction)99));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Action");
    }
}
```

- [ ] **Step 3: Run validator tests**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~Hotkeys" --configuration Release --verbosity normal
```

Expected: All tests pass.

---

## Task 13: Application — Handler tests

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/CreateHotkeyCommandHandlerTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/UpdateHotkeyCommandHandlerTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/GetHotkeyQueryHandlerTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/ListHotkeysQueryHandlerTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Hotkeys/DeleteHotkeyCommandHandlerTests.cs`

> **Reuse fixture:** `HotkeyDbFixture` + `[CollectionDefinition("HotkeyDb")]` already exist at `tests/AHKFlowApp.Application.Tests/Hotkeys/HotkeyDbFixture.cs`. Don't recreate. Helpers (`CurrentUserHelper`, `FixedClock`) are shared with the Hotstring tests; reuse the same patterns.

- [ ] **Step 1: Create CreateHotkeyCommandHandlerTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class CreateHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    private static CreateHotkeyDto Sample(
        string description = "Open Notepad",
        string key = "n",
        bool ctrl = false, bool alt = false, bool shift = false, bool win = false,
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true)
        => new(description, key, ctrl, alt, shift, win, HotkeyAction.Run, "notepad.exe", profileIds, appliesToAllProfiles);

    [Fact]
    public async Task Handle_WhenValid_AppliesToAll_CreatesAndReturnsDto()
    {
        await using AppDbContext db = fx.CreateContext();
        var owner = Guid.NewGuid();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(Sample()), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("Open Notepad");
        result.Value.Key.Should().Be("n");
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotkeys.CountAsync(h => h.OwnerOid == owner)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenValid_ProfileScoped_CreatesJunctionRows()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(Profile.Create(owner, "Work", true, "", "", _clock));
            await seed.SaveChangesAsync();
        }

        Guid actualProfileId;
        await using (AppDbContext verify = fx.CreateContext())
        {
            actualProfileId = (await verify.Profiles.FirstAsync(p => p.OwnerOid == owner)).Id;
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var dto = Sample(profileIds: [actualProfileId], appliesToAllProfiles: false);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(dto), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(actualProfileId);

        await using AppDbContext check = fx.CreateContext();
        (await check.HotkeyProfiles.CountAsync(hp => hp.ProfileId == actualProfileId)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(null), _clock);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(Sample()), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_DuplicateModifierCombo_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(Hotkey.Create(owner, "first", "n", true, false, false, false,
                HotkeyAction.Run, "x", true, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var dto = Sample(description: "second", key: "n", ctrl: true);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(dto), default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Handle_SameKeyDifferentModifiers_Succeeds()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(Hotkey.Create(owner, "first", "n", true, false, false, false,
                HotkeyAction.Run, "x", true, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        // Same key 'n', but Ctrl+Alt instead of just Ctrl — different combo, allowed.
        var dto = Sample(description: "second", key: "n", ctrl: true, alt: true);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(dto), default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_SameComboDifferentOwners_Succeeds()
    {
        var ownerA = Guid.NewGuid();
        var ownerB = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(Hotkey.Create(ownerA, "a", "n", true, false, false, false,
                HotkeyAction.Run, "x", true, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(ownerB), _clock);
        var dto = Sample(description: "b", key: "n", ctrl: true);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(dto), default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_ProfileScoped_UnknownProfileId_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var dto = Sample(profileIds: [Guid.NewGuid()], appliesToAllProfiles: false);

        Result<HotkeyDto> result = await handler.Handle(new CreateHotkeyCommand(dto), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }
}
```

- [ ] **Step 2: Create UpdateHotkeyCommandHandlerTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class UpdateHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenValid_UpdatesAndReturnsUpdatedDto()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var entity = Hotkey.Create(owner, "old", "n", false, false, false, false,
            HotkeyAction.Send, "old", true, clock);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), clock);
        var dto = new UpdateHotkeyDto("new", "n", true, false, false, false,
            HotkeyAction.Run, "notepad.exe", null, true);
        var cmd = new UpdateHotkeyCommand(entity.Id, dto);

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("new");
        result.Value.Ctrl.Should().BeTrue();
        result.Value.Action.Should().Be(HotkeyAction.Run);
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotkey.Create(owner, "x", "n", false, false, false, false,
            HotkeyAction.Send, "", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(attacker), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("y", "n", false, false, false, false,
                HotkeyAction.Send, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(Guid.NewGuid(),
            new UpdateHotkeyDto("x", "n", false, false, false, false,
                HotkeyAction.Send, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenDuplicateModifierCombo_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        var first = Hotkey.Create(owner, "first", "n", true, false, false, false,
            HotkeyAction.Send, "", true, TimeProvider.System);
        var second = Hotkey.Create(owner, "second", "m", true, false, false, false,
            HotkeyAction.Send, "", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System);
        // Try to update `second` so it collides with `first` (Ctrl+n)
        var cmd = new UpdateHotkeyCommand(second.Id,
            new UpdateHotkeyDto("second", "n", true, false, false, false,
                HotkeyAction.Send, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
```

- [ ] **Step 3: Create GetHotkeyQueryHandlerTests.cs**

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class GetHotkeyQueryHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_ReturnsDto()
    {
        var owner = Guid.NewGuid();
        var entity = Hotkey.Create(owner, "x", "n", false, false, false, false,
            HotkeyAction.Run, "p", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotkeyQueryHandler(db, CurrentUserHelper.For(owner));

        Result<HotkeyDto> result = await handler.Handle(new GetHotkeyQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();
        result.Value.Action.Should().Be(HotkeyAction.Run);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotkey.Create(owner, "x", "n", false, false, false, false,
            HotkeyAction.Run, "", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotkeyQueryHandler(db, CurrentUserHelper.For(attacker));

        Result<HotkeyDto> result = await handler.Handle(new GetHotkeyQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 4: Create ListHotkeysQueryHandlerTests.cs**

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class ListHotkeysQueryHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_ScopedToOwner_IgnoresOtherTenants()
    {
        var owner = Guid.NewGuid();
        var other = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(Hotkey.Create(owner, "mine", "a", false, false, false, false,
                HotkeyAction.Send, "", true, TimeProvider.System));
            seed.Hotkeys.Add(Hotkey.Create(other, "theirs", "b", false, false, false, false,
                HotkeyAction.Send, "", true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new ListHotkeysQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Should().OnlyContain(h => h.Description == "mine");
    }

    [Fact]
    public async Task Handle_FiltersByProfileId_IncludesProfileScopedAndGlobal()
    {
        var owner = Guid.NewGuid();
        Guid profileId;

        await using (AppDbContext seed = fx.CreateContext())
        {
            var profile = Profile.Create(owner, "Work", true, "", "", TimeProvider.System);
            seed.Profiles.Add(profile);
            var scoped = Hotkey.Create(owner, "scoped", "a", false, false, false, false,
                HotkeyAction.Send, "", false, TimeProvider.System);
            var global = Hotkey.Create(owner, "global", "b", false, false, false, false,
                HotkeyAction.Send, "", true, TimeProvider.System);
            var otherProfileScoped = Hotkey.Create(owner, "other", "c", false, false, false, false,
                HotkeyAction.Send, "", false, TimeProvider.System);
            seed.Hotkeys.AddRange(scoped, global, otherProfileScoped);
            await seed.SaveChangesAsync();
            profileId = profile.Id;
            seed.HotkeyProfiles.Add(HotkeyProfile.Create(scoped.Id, profileId));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(ProfileId: profileId), default);

        result.Value.Items.Should().HaveCount(2);
        result.Value.Items.Should().Contain(h => h.Description == "scoped");
        result.Value.Items.Should().Contain(h => h.Description == "global");
    }

    [Fact]
    public async Task Handle_Paginates_WithCorrectTotalCount()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

        await using (AppDbContext seed = fx.CreateContext())
        {
            for (int i = 0; i < 5; i++)
            {
                seed.Hotkeys.Add(Hotkey.Create(owner, $"hk{i}", $"k{i}", false, false, false, false,
                    HotkeyAction.Send, "", true, clock));
                clock.Advance(TimeSpan.FromSeconds(1));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> page2 = await handler.Handle(
            new ListHotkeysQuery(Page: 2, PageSize: 2), default);

        page2.Value.TotalCount.Should().Be(5);
        page2.Value.Items.Should().HaveCount(2);
        page2.Value.Page.Should().Be(2);
        page2.Value.PageSize.Should().Be(2);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(null));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new ListHotkeysQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Search_MatchesDescription()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(Hotkey.Create(owner, "Open Notepad", "n", false, false, false, false,
                HotkeyAction.Run, "notepad.exe", true, TimeProvider.System));
            seed.Hotkeys.Add(Hotkey.Create(owner, "Open Calculator", "c", false, false, false, false,
                HotkeyAction.Run, "calc.exe", true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "Notepad"), default);

        result.Value.Items.Should().ContainSingle().Which.Description.Should().Be("Open Notepad");
    }
}
```

- [ ] **Step 5: Create DeleteHotkeyCommandHandlerTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class DeleteHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_DeletesAndCascadesJunction()
    {
        var owner = Guid.NewGuid();
        Guid hotkeyId;
        Guid profileId;

        await using (AppDbContext seed = fx.CreateContext())
        {
            var profile = Profile.Create(owner, "Work", true, "", "", TimeProvider.System);
            var hotkey = Hotkey.Create(owner, "x", "n", false, false, false, false,
                HotkeyAction.Send, "", false, TimeProvider.System);
            seed.Profiles.Add(profile);
            seed.Hotkeys.Add(hotkey);
            await seed.SaveChangesAsync();
            seed.HotkeyProfiles.Add(HotkeyProfile.Create(hotkey.Id, profile.Id));
            await seed.SaveChangesAsync();
            hotkeyId = hotkey.Id;
            profileId = profile.Id;
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotkeyCommandHandler(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new DeleteHotkeyCommand(hotkeyId), default);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotkeys.AnyAsync(h => h.Id == hotkeyId)).Should().BeFalse();
        (await verify.HotkeyProfiles.AnyAsync(j => j.HotkeyId == hotkeyId)).Should().BeFalse();
        (await verify.Profiles.AnyAsync(p => p.Id == profileId)).Should().BeTrue();  // profile not affected
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotkey.Create(owner, "x", "n", false, false, false, false,
            HotkeyAction.Send, "", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotkeyCommandHandler(db, CurrentUserHelper.For(attacker));

        Result result = await handler.Handle(new DeleteHotkeyCommand(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 6: Run all Application tests**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --verbosity normal
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add tests/AHKFlowApp.Application.Tests/Hotkeys/
git commit -m "test(app): rebuild Hotkey handler + validator tests for target schema"
```

---

## Task 14: API integration tests

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/Hotkeys/HotkeysEndpointsTests.cs`

- [ ] **Step 1: Replace HotkeysEndpointsTests.cs**

Replace the entire file:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotkeys;

[Collection("WebApi")]
public sealed class HotkeysEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    private static CreateHotkeyDto Sample(
        string description = "Open Notepad",
        string key = "n",
        bool ctrl = false, bool alt = false, bool shift = false, bool win = false)
        => new(description, key, ctrl, alt, shift, win, HotkeyAction.Run, "notepad.exe");

    [Fact]
    public async Task Post_CreatesAndReturns201WithLocation()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", Sample());

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        HotkeyDto? body = await response.Content.ReadFromJsonAsync<HotkeyDto>();
        body!.Description.Should().Be("Open Notepad");
        body.Key.Should().Be("n");
        body.Action.Should().Be(HotkeyAction.Run);
        body.AppliesToAllProfiles.Should().BeTrue();
        body.ProfileIds.Should().BeEmpty();

        HttpResponseMessage get = await client.GetAsync(response.Headers.Location);
        get.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Post_InvalidBody_Returns400()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("", "", Action: HotkeyAction.Send);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Post_DuplicateModifierCombo_Returns409_WithProblemDetails()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        HttpResponseMessage first = await client.PostAsJsonAsync("/api/v1/hotkeys",
            Sample(description: "first", key: "n", ctrl: true));
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/hotkeys",
            Sample(description: "second", key: "n", ctrl: true));

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
        second.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await second.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("status").GetInt32().Should().Be(409);
        root.GetProperty("detail").GetString().Should().Contain("already exists");
    }

    [Fact]
    public async Task Put_UnknownId_Returns404_WithProblemDetails()
    {
        using HttpClient client = CreateAuthed();
        var dto = new UpdateHotkeyDto("x", "n", false, false, false, false,
            HotkeyAction.Send, "", null, true);

        var unknownId = Guid.NewGuid();
        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/hotkeys/{unknownId}", dto);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_OtherUsersRow_Returns404()
    {
        var ownerA = Guid.NewGuid();
        var ownerB = Guid.NewGuid();

        using HttpClient a = CreateAuthed(ownerA);
        HttpResponseMessage created = await a.PostAsJsonAsync("/api/v1/hotkeys",
            Sample(description: "tenant-a"));
        HotkeyDto? body = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        using HttpClient b = CreateAuthed(ownerB);
        HttpResponseMessage response = await b.PutAsJsonAsync(
            $"/api/v1/hotkeys/{body!.Id}",
            new UpdateHotkeyDto("hijack", "n", false, false, false, false,
                HotkeyAction.Send, "", null, true));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_Success_Returns200WithUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotkeys",
            Sample(description: "before", key: "n"));
        HotkeyDto? before = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        await Task.Delay(10);

        HttpResponseMessage put = await client.PutAsJsonAsync(
            $"/api/v1/hotkeys/{before!.Id}",
            new UpdateHotkeyDto("after", "n", true, false, false, false,
                HotkeyAction.Run, "calc.exe", null, true));

        put.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyDto? after = await put.Content.ReadFromJsonAsync<HotkeyDto>();
        after!.Description.Should().Be("after");
        after.Ctrl.Should().BeTrue();
        after.Action.Should().Be(HotkeyAction.Run);
        after.UpdatedAt.Should().BeOnOrAfter(before.CreatedAt);
    }

    [Fact]
    public async Task Delete_ThenGet_Returns404()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotkeys", Sample());
        HotkeyDto? body = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        HttpResponseMessage del = await client.DeleteAsync($"/api/v1/hotkeys/{body!.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        HttpResponseMessage get = await client.GetAsync($"/api/v1/hotkeys/{body.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task List_FiltersByProfileId_IncludesGlobal()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotkeys", Sample(description: "global", key: "g"));
        var anyProfileId = Guid.NewGuid();

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotkeys?profileId={anyProfileId}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.Items.Should().Contain(h => h.Description == "global" && h.AppliesToAllProfiles);
    }

    [Fact]
    public async Task List_WithPagination_ReturnsSlice()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        for (int i = 0; i < 5; i++)
            await client.PostAsJsonAsync("/api/v1/hotkeys",
                Sample(description: $"hk{i}", key: $"k{i}"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?page=2&pageSize=2");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.TotalCount.Should().Be(5);
        body.Items.Should().HaveCount(2);
        body.Page.Should().Be(2);
    }

    [Fact]
    public async Task List_PageSizeTooLarge_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?pageSize=500");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task List_SearchByDescription_FiltersResults()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotkeys", Sample(description: "Open Notepad", key: "n"));
        await client.PostAsJsonAsync("/api/v1/hotkeys", Sample(description: "Open Calculator", key: "c"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?search=Notepad");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.Items.Should().ContainSingle().Which.Description.Should().Be("Open Notepad");
    }

    [Fact]
    public async Task List_SearchTooLong_Returns400()
    {
        using HttpClient client = CreateAuthed();
        string longSearch = new('x', 201);

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotkeys?search={longSearch}");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Get_WithoutBearer_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_WithoutScope_Returns403()
    {
        using HttpClient client = _factory.WithTestAuth(b =>
            b.WithOid(Guid.NewGuid()).WithoutScope()).CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Post_InvalidBody_ReturnsProblemDetailsWithErrors()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("", "", Action: HotkeyAction.Send);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;

        root.GetProperty("title").GetString().Should().Be("Validation failed");
        root.GetProperty("status").GetInt32().Should().Be(400);

        JsonElement errors = root.GetProperty("errors");
        errors.TryGetProperty("Input.Description", out _).Should().BeTrue();
        errors.TryGetProperty("Input.Key", out _).Should().BeTrue();
    }

    public void Dispose() => _factory.Dispose();
}
```

- [ ] **Step 2: Run API tests**

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/AHKFlowApp.API.Tests/Hotkeys/HotkeysEndpointsTests.cs
git commit -m "test(api): rebuild Hotkey endpoint tests for target schema"
```

---

## Task 15: Frontend — DTOs

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyDto.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotkeyDto.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotkeyDto.cs`

> **Note on enum location:** the frontend project does not reference `AHKFlowApp.Domain`. Mirror the enum on the frontend side so JSON deserializes cleanly.

- [ ] **Step 1: Create HotkeyAction enum mirror**

Create `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotkeyAction.cs`:

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public enum HotkeyAction
{
    Send = 0,
    Run = 1,
}
```

- [ ] **Step 2: Create HotkeyDto.cs**

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
    HotkeyAction Action,
    string Parameters,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
```

- [ ] **Step 3: Create CreateHotkeyDto.cs**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

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
```

- [ ] **Step 4: Create UpdateHotkeyDto.cs**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

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

---

## Task 16: Frontend — API client + DI

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeysApiClient.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/HotkeysApiClient.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

- [ ] **Step 1: Create IHotkeysApiClient.cs**

```csharp
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IHotkeysApiClient
{
    Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(Guid? profileId, int page, int pageSize, string? search = null, bool ignoreCase = true, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> CreateAsync(CreateHotkeyDto input, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
```

- [ ] **Step 2: Create HotkeysApiClient.cs**

```csharp
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotkeysApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IHotkeysApiClient
{
    private const string BasePath = "api/v1/hotkeys";

    public Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(Guid? profileId, int page, int pageSize, string? search = null, bool ignoreCase = true, CancellationToken ct = default)
    {
        string query = $"?page={page}&pageSize={pageSize}";
        if (profileId is { } pid) query += $"&profileId={pid}";
        if (!string.IsNullOrWhiteSpace(search)) query += $"&search={Uri.EscapeDataString(search)}";
        if (!ignoreCase) query += "&ignoreCase=false";
        return SendAsync<PagedList<HotkeyDto>>(HttpMethod.Get, BasePath + query, content: null, ct);
    }

    public Task<ApiResult<HotkeyDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotkeyDto>> CreateAsync(CreateHotkeyDto input, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotkeyDto>> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);
}
```

- [ ] **Step 3: Register the client in Program.cs**

In `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, find the existing `IHotstringsApiClient` registration and add an analogous line for hotkeys directly below it. The exact registration line should mirror what already exists for hotstrings (typically `builder.Services.AddHttpClient<IHotkeysApiClient, HotkeysApiClient>(...)` with the same base address + auth handler config). If the existing registration uses an extension method, add the analogous call.

Search for `IHotstringsApiClient` to locate the spot and copy the pattern verbatim, swapping the type pair.

```bash
# Locate the existing registration:
rg "IHotstringsApiClient" src/Frontend/AHKFlowApp.UI.Blazor/Program.cs
```

After your edit, both `IHotstringsApiClient` and `IHotkeysApiClient` should appear in `Program.cs` with identical registration patterns.

---

## Task 17: Frontend — EditModel

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotkeyEditModel.cs`

- [ ] **Step 1: Create HotkeyEditModel.cs**

```csharp
using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotkeyEditModel
{
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
    public HotkeyAction Action { get; set; } = HotkeyAction.Send;

    [MaxLength(4000, ErrorMessage = "Parameters must be 4000 characters or fewer.")]
    public string Parameters { get; set; } = "";

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];

    public static HotkeyEditModel FromDto(HotkeyDto dto) => new()
    {
        Id = dto.Id,
        Description = dto.Description,
        Key = dto.Key,
        Ctrl = dto.Ctrl,
        Alt = dto.Alt,
        Shift = dto.Shift,
        Win = dto.Win,
        Action = dto.Action,
        Parameters = dto.Parameters,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
    };

    public CreateHotkeyDto ToCreateDto() =>
        new(Description, Key, Ctrl, Alt, Shift, Win, Action, Parameters,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles);

    public UpdateHotkeyDto ToUpdateDto() =>
        new(Description, Key, Ctrl, Alt, Shift, Win, Action, Parameters,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles);
}
```

---

## Task 18: Frontend — Hotkeys page

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor`

- [ ] **Step 1: Replace Hotkeys.razor**

Replace the entire content (currently a stub):

```razor
@page "/hotkeys"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor
@using Microsoft.AspNetCore.Components.Authorization
@implements IDisposable

<PageTitle>Hotkeys</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Hotkeys</MudText>

<MudPaper Class="pa-4">
    <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="2" Wrap="Wrap.Wrap" Class="mb-4">
        <MudButton Class="add-hotkey" Variant="Variant.Filled" Color="Color.Primary"
                   StartIcon="@Icons.Material.Filled.Add" OnClick="StartAddAsync"
                   Disabled="@(!_isAuthenticated || _editing.ContainsKey(Guid.Empty))">
            Add
        </MudButton>
        <MudButton Class="reload-hotkeys" Variant="Variant.Filled" Color="Color.Secondary"
                   StartIcon="@Icons.Material.Filled.Refresh" OnClick="ReloadAsync"
                   Disabled="@(!_isAuthenticated || _loading)">
            Reload
        </MudButton>
        <MudSpacer />
        <MudTextField T="string" @bind-Value="_search" @bind-Value:after="OnSearchChangedAsync"
                      DebounceInterval="300"
                      Placeholder="Search Hotkeys"
                      Adornment="Adornment.Start"
                      AdornmentIcon="@Icons.Material.Filled.Search"
                      Class="search-hotkeys"
                      Style="max-width: 360px;"
                      Immediate="true" />
    </MudStack>

    @if (_loadError is not null)
    {
        <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
    }

    <div style="overflow-x: auto;">
        <MudTable @ref="_table" T="HotkeyDto" ServerData="LoadServerData"
                  Dense="true" Hover="true" RowsPerPage="_rowsPerPage" Loading="_loading">
            <HeaderContent>
                <MudTh>Description</MudTh>
                <MudTh>Key</MudTh>
                <MudTh>Ctrl</MudTh>
                <MudTh>Alt</MudTh>
                <MudTh>Shift</MudTh>
                <MudTh>Win</MudTh>
                <MudTh>Action</MudTh>
                <MudTh>Profiles</MudTh>
                <MudTh>Parameters</MudTh>
                <MudTh Style="width:160px">Actions</MudTh>
            </HeaderContent>
            <RowTemplate>
                @if (_editing.TryGetValue(context.Id, out var edit))
                {
                    bool showErrors = _commitAttempted.Contains(context.Id);
                    string? descError = showErrors ? ValidateDescription(edit.Description) : null;
                    string? keyError = showErrors ? ValidateKey(edit.Key) : null;
                    <MudTd>
                        <MudTextField @bind-Value="edit.Description"
                                      Validation="@(new Func<string, string?>(ValidateDescription))"
                                      Error="@(descError is not null)" ErrorText="@descError"
                                      Immediate="true" MaxLength="200"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "description-input" })" />
                    </MudTd>
                    <MudTd>
                        <MudTextField @bind-Value="edit.Key"
                                      Validation="@(new Func<string, string?>(ValidateKey))"
                                      Error="@(keyError is not null)" ErrorText="@keyError"
                                      Immediate="true" MaxLength="20"
                                      Style="max-width: 80px;"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "key-input" })" />
                    </MudTd>
                    <MudTd><MudCheckBox T="bool" @bind-Value="edit.Ctrl" /></MudTd>
                    <MudTd><MudCheckBox T="bool" @bind-Value="edit.Alt" /></MudTd>
                    <MudTd><MudCheckBox T="bool" @bind-Value="edit.Shift" /></MudTd>
                    <MudTd><MudCheckBox T="bool" @bind-Value="edit.Win" /></MudTd>
                    <MudTd>
                        <MudSelect T="HotkeyAction" @bind-Value="edit.Action" Dense="true"
                                   UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "action-select" })">
                            <MudSelectItem T="HotkeyAction" Value="HotkeyAction.Send">Send</MudSelectItem>
                            <MudSelectItem T="HotkeyAction" Value="HotkeyAction.Run">Run</MudSelectItem>
                        </MudSelect>
                    </MudTd>
                    <MudTd>
                        <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="1">
                            <MudCheckBox T="bool" @bind-Value="edit.AppliesToAllProfiles" Label="Any"
                                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "applies-to-all-checkbox" })" />
                            @if (!edit.AppliesToAllProfiles)
                            {
                                <MudSelect T="Guid" MultiSelection="true"
                                           SelectedValues="@edit.ProfileIds"
                                           SelectedValuesChanged="@(ids => edit.ProfileIds = [.. ids])"
                                           ToStringFunc="@(id => _profiles.FirstOrDefault(p => p.Id == id)?.Name ?? id.ToString())"
                                           Dense="true" Placeholder="Select"
                                           UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "profile-select" })">
                                    @foreach (var profile in _profiles)
                                    {
                                        <MudSelectItem T="Guid" Value="@profile.Id">@profile.Name</MudSelectItem>
                                    }
                                </MudSelect>
                            }
                        </MudStack>
                    </MudTd>
                    <MudTd>
                        <MudTextField @bind-Value="edit.Parameters" Immediate="true" MaxLength="4000"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "parameters-input" })" />
                    </MudTd>
                    <MudTd>
                        <MudIconButton Class="commit-edit" Icon="@Icons.Material.Filled.Check"
                                       Color="Color.Success" OnClick="() => CommitEditAsync(context.Id)" />
                        <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.Close"
                                       Color="Color.Default" OnClick="() => CancelEditAsync(context.Id)" />
                    </MudTd>
                }
                else
                {
                    <MudTd>@context.Description</MudTd>
                    <MudTd>@context.Key</MudTd>
                    <MudTd><MudCheckBox T="bool" Value="@context.Ctrl" ReadOnly="true" /></MudTd>
                    <MudTd><MudCheckBox T="bool" Value="@context.Alt" ReadOnly="true" /></MudTd>
                    <MudTd><MudCheckBox T="bool" Value="@context.Shift" ReadOnly="true" /></MudTd>
                    <MudTd><MudCheckBox T="bool" Value="@context.Win" ReadOnly="true" /></MudTd>
                    <MudTd>@context.Action</MudTd>
                    <MudTd>
                        @if (context.AppliesToAllProfiles)
                        {
                            <MudChip T="string" Size="Size.Small" Color="Color.Info">Any</MudChip>
                        }
                        else
                        {
                            @foreach (var pid in context.ProfileIds)
                            {
                                var name = _profiles.FirstOrDefault(p => p.Id == pid)?.Name ?? pid.ToString()[..8];
                                <MudChip T="string" Size="Size.Small">@name</MudChip>
                            }
                        }
                    </MudTd>
                    <MudTd>@context.Parameters</MudTd>
                    <MudTd>
                        <MudIconButton Class="delete" Icon="@Icons.Material.Filled.Delete" Color="Color.Error"
                                       OnClick="() => DeleteAsync(context)" />
                        <MudIconButton Class="start-edit" Icon="@Icons.Material.Filled.Edit"
                                       OnClick="() => StartEdit(context)" />
                    </MudTd>
                }
            </RowTemplate>
            <NoRecordsContent><MudText>No hotkeys yet.</MudText></NoRecordsContent>
            <PagerContent>
                <MudTablePager PageSizeOptions="UserPreferences.AllowedRowsPerPage" />
            </PagerContent>
        </MudTable>
    </div>
</MudPaper>

@code {
    [CascadingParameter] private Task<AuthenticationState>? AuthState { get; set; }
    [Inject] private IHotkeysApiClient Api { get; set; } = default!;
    [Inject] private IProfilesApiClient ProfilesApi { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;
    [Inject] private IUserPreferencesService Preferences { get; set; } = default!;

    private MudTable<HotkeyDto>? _table;
    private readonly Dictionary<Guid, HotkeyEditModel> _editing = new();
    private readonly HashSet<Guid> _commitAttempted = [];
    private List<ProfileDto> _profiles = [];
    private bool _isAuthenticated;
    private bool _loading;
    private string? _loadError;
    private string _search = "";
    private int _rowsPerPage = UserPreferences.Default.RowsPerPage;
    private readonly CancellationTokenSource _cts = new();

    private static readonly HotkeyDto _draftPlaceholder = new(
        Guid.Empty, [], true, "", "", false, false, false, false,
        HotkeyAction.Send, "", DateTimeOffset.MinValue, DateTimeOffset.MinValue);

    protected override async Task OnInitializedAsync()
    {
        if (AuthState is not null)
        {
            var state = await AuthState;
            _isAuthenticated = state.User.Identity?.IsAuthenticated ?? false;
        }

        UserPreferences prefs = await Preferences.GetAsync();
        _rowsPerPage = prefs.RowsPerPage;

        if (_isAuthenticated)
        {
            ApiResult<List<ProfileDto>> profilesResult = await ProfilesApi.ListAsync(_cts.Token);
            if (profilesResult.IsSuccess)
                _profiles = profilesResult.Value ?? [];
        }
    }

    private async Task<TableData<HotkeyDto>> LoadServerData(TableState state, CancellationToken ct)
    {
        _loading = true;
        _loadError = null;

        ApiResult<PagedList<HotkeyDto>> result = await Api.ListAsync(
            profileId: null,
            page: state.Page + 1,
            pageSize: state.PageSize,
            search: string.IsNullOrWhiteSpace(_search) ? null : _search,
            ignoreCase: true,
            ct: ct);

        _loading = false;

        if (!result.IsSuccess)
        {
            _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
            await InvokeAsync(StateHasChanged);
            return new TableData<HotkeyDto> { Items = [], TotalItems = 0 };
        }

        List<HotkeyDto> items = [.. result.Value!.Items];
        if (state.Page == 0 && _editing.ContainsKey(Guid.Empty))
            items.Insert(0, _draftPlaceholder);

        return new TableData<HotkeyDto> { Items = items, TotalItems = result.Value.TotalCount };
    }

    private async Task ReloadAsync()
    {
        if (_table is not null) await _table.ReloadServerData();
    }

    private async Task OnSearchChangedAsync()
    {
        if (_table is not null) await _table.ReloadServerData();
    }

    private async Task StartAddAsync()
    {
        _editing[Guid.Empty] = new HotkeyEditModel();
        if (_table is not null) await _table.ReloadServerData();
    }

    private void StartEdit(HotkeyDto dto) =>
        _editing[dto.Id] = HotkeyEditModel.FromDto(dto);

    private async Task CancelEditAsync(Guid id)
    {
        _editing.Remove(id);
        _commitAttempted.Remove(id);
        if (id == Guid.Empty && _table is not null) await _table.ReloadServerData();
    }

    private static string? ValidateDescription(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "Description is required";
        if (value.Length > 200) return "Description must be 200 characters or fewer";
        return null;
    }

    private static string? ValidateKey(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "Key is required";
        if (value.Length > 20) return "Key must be 20 characters or fewer";
        return null;
    }

    private async Task CommitEditAsync(Guid id)
    {
        if (!_editing.TryGetValue(id, out HotkeyEditModel? edit)) return;

        _commitAttempted.Add(id);
        if (ValidateDescription(edit.Description) is not null || ValidateKey(edit.Key) is not null)
            return;

        _commitAttempted.Remove(id);

        if (id == Guid.Empty)
        {
            ApiResult<HotkeyDto> result = await Api.CreateAsync(edit.ToCreateDto(), _cts.Token);
            if (result.IsSuccess)
            {
                _editing.Remove(id);
                Snackbar.Add("Hotkey created.", Severity.Success);
                if (_table is not null) await _table.ReloadServerData();
            }
            else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
        else
        {
            ApiResult<HotkeyDto> result = await Api.UpdateAsync(id, edit.ToUpdateDto(), _cts.Token);
            if (result.IsSuccess)
            {
                _editing.Remove(id);
                Snackbar.Add("Hotkey updated.", Severity.Success);
                if (_table is not null) await _table.ReloadServerData();
            }
            else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }

    private async Task DeleteAsync(HotkeyDto dto)
    {
        bool? confirm = await DialogService.ShowMessageBoxAsync(
            title: "Delete hotkey?",
            message: $"Delete \"{dto.Description}\"? This cannot be undone.",
            yesText: "Delete", cancelText: "Cancel");
        if (confirm != true) return;

        ApiResult result = await Api.DeleteAsync(dto.Id, _cts.Token);
        if (result.IsSuccess)
        {
            Snackbar.Add("Hotkey deleted.", Severity.Success);
            if (_table is not null) await _table.ReloadServerData();
        }
        else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

---

## Task 19: Frontend — API client tests

**Files:**
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs`

- [ ] **Step 1: Create HotkeysApiClientTests.cs**

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotkeysApiClientTests
{
    private static HotkeysApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task ListAsync_OnSuccess_ReturnsPagedList()
    {
        var paged = new PagedList<HotkeyDto>(
            Items: [new HotkeyDto(Guid.NewGuid(), [], true, "Open Notepad", "n", true, false, false, false,
                HotkeyAction.Run, "notepad.exe", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)],
            Page: 1, PageSize: 50, TotalCount: 1, TotalPages: 1, HasNextPage: false, HasPreviousPage: false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        ApiResult<PagedList<HotkeyDto>> result = await ClientWith(handler).ListAsync(profileId: null, page: 1, pageSize: 50);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/hotkeys?page=1&pageSize=50");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Modifier combo already exists", "/api/v1/hotkeys", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        var dto = new CreateHotkeyDto("Open Notepad", "n", Ctrl: true);
        ApiResult<HotkeyDto> result = await ClientWith(handler).CreateAsync(dto);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task ListAsync_WithProfileId_AppendsProfileIdToQueryString()
    {
        var profileId = Guid.NewGuid();
        var paged = new PagedList<HotkeyDto>([], 1, 50, 0, 0, false, false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(profileId: profileId, page: 1, pageSize: 50);

        handler.LastRequest!.RequestUri!.Query.Should().Contain($"profileId={profileId}");
    }

    [Fact]
    public async Task DeleteAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound,
            new ApiProblemDetails(null, "Not Found", 404, null, null, null));

        ApiResult result = await ClientWith(handler).DeleteAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;
        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        { LastRequest = request; return Task.FromResult(_response); }
    }
}
```

---

## Task 20: Final build + test sweep

- [ ] **Step 1: Build everything**

```bash
dotnet build --configuration Release
```

Expected: `Build succeeded.` with 0 errors.

- [ ] **Step 2: Run all tests**

```bash
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: All tests pass.

- [ ] **Step 3: Format**

```bash
dotnet format
```

Expected: No formatting changes (or commit them in the next step).

- [ ] **Step 4: Commit frontend + final**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/
git add tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs
git commit -m "feat(ui): rebuild Hotkeys page with structured fields + profile multi-select"
```

---

## Task 21: Open PR

- [ ] **Step 1: Push branch**

```bash
git push -u origin feature/022b-hotkey-schema-rebuild
```

- [ ] **Step 2: Create PR**

```bash
gh pr create \
  --base feature/024b-many-to-many-profile-association \
  --title "feat: phase 3 — hotkey schema rebuild + M2M profile association" \
  --body "$(cat <<'EOF'
## Summary
- Rebuilds `Hotkey` from free-form `Trigger`/`Action`/`Description` strings to structured fields: `Description`, `Key`, `Ctrl`/`Alt`/`Shift`/`Win`, `HotkeyAction` enum, `Parameters`, `AppliesToAllProfiles`
- Adds `HotkeyProfile` junction; unique index `IX_Hotkey_Owner_Modifiers` on `(OwnerOid, Key, Ctrl, Alt, Shift, Win)`
- Destructive migration: drops old columns + filtered indexes, adds new schema (dev-only per spec D7)
- Rebuilds DTOs / validators / handlers / queries; conflict pre-check is now 5-column equality
- New `IHotkeysApiClient` + `HotkeysApiClient` on the frontend (didn't exist before)
- Stub `Hotkeys.razor` replaced with full inline-edit MudTable: Description, Key, 4 modifier checkboxes, Action select, Profile multi-select + "Any", Parameters
- Old 021/022 endpoint tests rewritten; new validator + handler + delete + list tests added
- Hotstring untouched

## Test plan
- [ ] `dotnet test --configuration Release` passes
- [ ] Manual: create hotkey with Ctrl+n, then try Ctrl+n again → 409
- [ ] Manual: same `n` with Ctrl+Alt vs just Ctrl → both succeed (different combos)
- [ ] Manual: create with "Any" → ProfileIds empty
- [ ] Manual: create with two profiles selected → ProfileIds has both
- [ ] Manual: filter list by profileId → shows global + scoped
- [ ] Manual: delete hotkey → junction rows cascade-deleted; profile row untouched

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

After writing this plan:

1. **Spec coverage (backlog 022b acceptance criteria):**
   - ✅ Fields: `Description (≤200, required)`, `Key (≤20, required)`, `Ctrl/Alt/Shift/Win` bools, `Action` enum, `Parameters (≤4000)`, `AppliesToAllProfiles` — Tasks 3, 5, 7, 8
   - ✅ `HotkeyAction` enum `Send=0, Run=1` — Task 1
   - ✅ Migration drops `Trigger`/`Action`/`Description`/`ProfileId` + both filtered indexes; adds new fields — Task 6
   - ✅ Unique index `IX_Hotkey_Owner_Modifiers` on `(OwnerOid, Key, Ctrl, Alt, Shift, Win)` — Task 5 step 2
   - ✅ DTOs reflect new shape; controller already shape-agnostic; handlers + validators rebuilt — Tasks 7–11
   - ✅ Existing 021 + 022 tests deleted/rewritten; new unit + integration tests cover the rebuild — Tasks 12–14, 19

2. **Phase 3 deltas vs Phase 2 (advisor checks):**
   - ✅ Migration uses `DropColumn`+`AddColumn` for `Action` (string→int) — Task 6 step 2 calls this out explicitly
   - ✅ Two filtered indexes dropped, new composite unfiltered unique index added with explicit name — Task 6 step 2
   - ✅ Boolean defaults `false` — Task 6 step 2
   - ✅ Conflict pre-check is 5-column equality — Tasks 10 step 1 (Create), no Update pre-check (relies on DB unique violation)
   - ✅ List profile filter uses junction OR `AppliesToAllProfiles` — Task 11 step 2
   - ✅ Frontend built from zero (DTOs, ApiClient, EditModel, Page replacement, DI registration) — Tasks 15–18, plus tests in Task 19
   - ✅ `HotkeyBuilder` full rewrite — Task 4
   - ✅ Inline edit despite >6 fields, with `overflow-x: auto` wrapper — Task 18 step 1

3. **Type consistency:**
   - `Hotkey.Create(ownerOid, description, key, ctrl, alt, shift, win, action, parameters, appliesToAllProfiles, clock)` — same signature in Task 3, used identically in Tasks 10, 12, 13.
   - `HotkeyProfile.Create(hotkeyId, profileId)` — Task 2, used in Tasks 10, 13.
   - `HotkeyDto(Id, ProfileIds, AppliesToAllProfiles, Description, Key, Ctrl, Alt, Shift, Win, Action, Parameters, CreatedAt, UpdatedAt)` — same field order on backend (Task 7), frontend (Task 15), and bUnit test stub (Task 19).
   - `CreateHotkeyDto` parameter order matches between `Sample()` helpers in Tasks 13 and 14.

4. **One thing for the executor to watch:**
   - The `IAppDbContext.Entry<TEntity>` accessor is assumed to exist from Phase 2 (used in `CreateHotkeyCommandHandler` to load junction after save). If your branch base lacks it, the Task 5 step 3 file content already includes it; verify the `using Microsoft.EntityFrameworkCore.ChangeTracking` doesn't trip up other consumers.

---

## Unresolved questions

- Per-profile uniqueness vs global uniqueness for hotkeys? Plan = global per owner. Confirm: spec says `(OwnerOid, Key, Ctrl, Alt, Shift, Win)` unfiltered → matches plan.
- `Parameters` required when `Action = Send`? Plan = optional/empty default. Spec silent. Defer.
- Validate `Key` against AHK key list? Plan = plain max-length + whitespace. Spec defers key-capture widget; format-check also out of scope.
