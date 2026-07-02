# Entity Version History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a before-image history table for Hotstrings and Hotkeys so users can view, revert, restore, and purge past versions — per spec `docs/superpowers/specs/2026-07-01-entity-version-history-design.md`.

**Architecture:** App-level snapshot capture. Handlers snapshot the current aggregate into a new `EntityHistory` table (JSON before-images) before every update/delete; new MediatR commands/queries expose history, revert, Recycle Bin, restore, and purge; six new endpoints per entity controller; Blazor gets a History dialog per entity page plus a Recycle Bin page.

**Tech Stack:** .NET 10, EF Core + SQL Server, MediatR + Ardalis.Result, FluentValidation, System.Text.Json, MudBlazor 9, xUnit + FluentAssertions + NSubstitute + Testcontainers + bUnit.

## Global Constraints

- Clean Architecture: API → Infrastructure → Application → Domain; Domain/Application have no EF-infrastructure references (`DbSet` via `IAppDbContext` is the established exception).
- Primary constructors, records for DTOs/commands/queries, file-scoped namespaces, `sealed` by default, collection expressions.
- Handlers return `Result<T>`; no exceptions for flow control; `TimeProvider` (never `DateTime.UtcNow`); propagate `CancellationToken` everywhere.
- Every public Application DTO record needs full XML docs — `ApplicationDtoXmlDocCoverageTests` fails the build gate otherwise.
- Every controller action needs `[ProducesResponseType]` attributes — `ProducesResponseTypeCoverageTests` enforces this.
- Integration tests: Testcontainers only (never `UseInMemoryDatabase`); test classes using a DB fixture need `[Trait("Category", "Integration")]` (enforced by `IntegrationTraitGuardTests`).
- Test naming `MethodName_Scenario_ExpectedResult`, AAA with blank lines.
- Conventional commits, extremely concise messages; feature + its tests = one commit.
- Retention constant: **50** versions per item. Snapshot schema version constant: **1**.
- MudBlazor markup: verify parameters/enums against the `mcp__mudblazor__*` MCP tools before writing new component markup (pinned MudBlazor 9.3.0).
- Build/test commands (run from repo root):
  - `dotnet build`
  - `dotnet test tests/<Project> --filter "FullyQualifiedName~<Class>" -v minimal`
- v1 UI scope: History action on the **desktop grid** only (mobile branch deferred); Recycle Bin is a desktop-first page.

## File Structure

```
src/Backend/AHKFlowApp.Domain/
  Enums/TrackedEntityType.cs                     (new)
  Enums/HistoryChangeType.cs                     (new)
  Entities/EntityHistory.cs                      (new)
  Entities/Hotstring.cs                          (add Restore factory)
  Entities/Hotkey.cs                             (add Restore factory)

src/Backend/AHKFlowApp.Application/
  Abstractions/IAppDbContext.cs                  (add EntityHistories DbSet)
  Abstractions/IEntityHistoryRecorder.cs         (new)
  Services/EntityHistoryRecorder.cs              (new)
  Common/HistorySaveRetry.cs                     (new)
  DTOs/HistorySnapshots.cs                       (new)
  DTOs/HistoryDtos.cs                            (new)
  Commands/Hotstrings/{Update,Delete,BulkDelete…}Command.cs  (wire capture)
  Commands/Hotkeys/{Update,Delete,BulkDelete…}Command.cs     (wire capture)
  Commands/Hotstrings/RevertHotstringCommand.cs  (new)
  Commands/Hotstrings/RestoreHotstringCommand.cs (new)
  Commands/Hotstrings/PurgeDeletedHotstringCommand.cs (new)
  Commands/Hotkeys/RevertHotkeyCommand.cs        (new)
  Commands/Hotkeys/RestoreHotkeyCommand.cs       (new)
  Commands/Hotkeys/PurgeDeletedHotkeyCommand.cs  (new)
  Queries/Hotstrings/GetHotstringHistoryQuery.cs (new)
  Queries/Hotstrings/GetHotstringHistoryVersionQuery.cs (new)
  Queries/Hotstrings/ListDeletedHotstringsQuery.cs (new)
  Queries/Hotkeys/GetHotkeyHistoryQuery.cs       (new)
  Queries/Hotkeys/GetHotkeyHistoryVersionQuery.cs (new)
  Queries/Hotkeys/ListDeletedHotkeysQuery.cs     (new)
  DependencyInjection.cs                         (register recorder)

src/Backend/AHKFlowApp.Infrastructure/
  Persistence/AppDbContext.cs                    (add DbSet)
  Persistence/Configurations/EntityHistoryConfiguration.cs (new)
  Migrations/<timestamp>_AddEntityHistory.cs     (generated)

src/Backend/AHKFlowApp.API/
  Controllers/HotstringsController.cs            (6 new actions)
  Controllers/HotkeysController.cs               (6 new actions)

src/Frontend/AHKFlowApp.UI.Blazor/
  DTOs/HistoryDtos.cs                            (new, frontend copies)
  Services/IHotstringsApiClient.cs + HotstringsApiClient.cs (6 new methods)
  Services/IHotkeysApiClient.cs + HotkeysApiClient.cs       (6 new methods)
  Components/Hotstrings/HotstringHistoryDialog.razor (new)
  Components/Hotkeys/HotkeyHistoryDialog.razor   (new)
  Pages/RecycleBin.razor                         (new)
  Pages/Hotstrings.razor / Hotkeys.razor         (History action, delete copy)
  Layout/NavMenu.razor                           (Recycle Bin link)

tests/
  AHKFlowApp.Domain.Tests/Entities/EntityHistoryTests.cs        (new)
  AHKFlowApp.Domain.Tests/Entities/RestoreFactoryTests.cs       (new)
  AHKFlowApp.Application.Tests/History/HistoryDbFixture.cs      (new fixture + collection)
  AHKFlowApp.Application.Tests/History/*.cs                     (recorder, capture, queries, revert, restore, purge tests)
  AHKFlowApp.API.Tests/Hotstrings/HotstringHistoryEndpointsTests.cs (new)
  AHKFlowApp.API.Tests/Hotkeys/HotkeyHistoryEndpointsTests.cs   (new)
  AHKFlowApp.UI.Blazor.Tests/Services/*ApiClientTests.cs        (new methods)
  AHKFlowApp.UI.Blazor.Tests/Components/**/History dialog tests (new)
  AHKFlowApp.UI.Blazor.Tests/Pages/RecycleBinPageTests.cs       (new)
```

---

### Task 1: Domain — enums, EntityHistory entity, Restore factories

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Enums/TrackedEntityType.cs`
- Create: `src/Backend/AHKFlowApp.Domain/Enums/HistoryChangeType.cs`
- Create: `src/Backend/AHKFlowApp.Domain/Entities/EntityHistory.cs`
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (add `Restore` after `Create`)
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` (add `Restore` after `Create`)
- Test: `tests/AHKFlowApp.Domain.Tests/Entities/EntityHistoryTests.cs`
- Test: `tests/AHKFlowApp.Domain.Tests/Entities/RestoreFactoryTests.cs`

**Interfaces:**
- Consumes: existing `Hotstring`/`Hotkey` entities, `HotkeyAction` enum.
- Produces: `TrackedEntityType { Hotstring = 1, Hotkey = 2 }`, `HistoryChangeType { Edit = 1, Delete = 2 }`, `EntityHistory.Create(Guid ownerOid, TrackedEntityType entityType, Guid entityId, int version, HistoryChangeType changeType, int schemaVersion, string snapshotJson, TimeProvider clock)`, `EntityHistory.ReassignVersion(int)`, `Hotstring.Restore(...)`, `Hotkey.Restore(...)` (exact signatures below).

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Domain.Tests/Entities/EntityHistoryTests.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class EntityHistoryTests
{
    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    [Fact]
    public void Create_SetsAllFieldsAndCapturedAtFromClock()
    {
        var ownerOid = Guid.NewGuid();
        var entityId = Guid.NewGuid();
        DateTimeOffset now = DateTimeOffset.Parse("2026-07-01T10:00:00Z");

        EntityHistory entry = EntityHistory.Create(
            ownerOid, TrackedEntityType.Hotstring, entityId, 3,
            HistoryChangeType.Edit, 1, "{}", new FixedClock(now));

        entry.Id.Should().NotBeEmpty();
        entry.OwnerOid.Should().Be(ownerOid);
        entry.EntityType.Should().Be(TrackedEntityType.Hotstring);
        entry.EntityId.Should().Be(entityId);
        entry.Version.Should().Be(3);
        entry.ChangeType.Should().Be(HistoryChangeType.Edit);
        entry.SchemaVersion.Should().Be(1);
        entry.SnapshotJson.Should().Be("{}");
        entry.CapturedAt.Should().Be(now);
    }

    [Fact]
    public void ReassignVersion_ReplacesVersion()
    {
        EntityHistory entry = EntityHistory.Create(
            Guid.NewGuid(), TrackedEntityType.Hotkey, Guid.NewGuid(), 1,
            HistoryChangeType.Delete, 1, "{}", TimeProvider.System);

        entry.ReassignVersion(7);

        entry.Version.Should().Be(7);
    }
}
```

`tests/AHKFlowApp.Domain.Tests/Entities/RestoreFactoryTests.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class RestoreFactoryTests
{
    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    [Fact]
    public void HotstringRestore_KeepsOriginalIdAndCreatedAt_SetsUpdatedAtFromClock()
    {
        var id = Guid.NewGuid();
        var ownerOid = Guid.NewGuid();
        DateTimeOffset createdAt = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        DateTimeOffset now = DateTimeOffset.Parse("2026-07-01T10:00:00Z");

        Hotstring entity = Hotstring.Restore(
            id, ownerOid, "btw", "by the way", "desc",
            appliesToAllProfiles: false, isEndingCharacterRequired: true,
            isTriggerInsideWord: false, createdAt, new FixedClock(now));

        entity.Id.Should().Be(id);
        entity.OwnerOid.Should().Be(ownerOid);
        entity.Trigger.Should().Be("btw");
        entity.Replacement.Should().Be("by the way");
        entity.Description.Should().Be("desc");
        entity.AppliesToAllProfiles.Should().BeFalse();
        entity.IsEndingCharacterRequired.Should().BeTrue();
        entity.IsTriggerInsideWord.Should().BeFalse();
        entity.CreatedAt.Should().Be(createdAt);
        entity.UpdatedAt.Should().Be(now);
    }

    [Fact]
    public void HotkeyRestore_KeepsOriginalIdAndCreatedAt_SetsUpdatedAtFromClock()
    {
        var id = Guid.NewGuid();
        var ownerOid = Guid.NewGuid();
        DateTimeOffset createdAt = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        DateTimeOffset now = DateTimeOffset.Parse("2026-07-01T10:00:00Z");

        Hotkey entity = Hotkey.Restore(
            id, ownerOid, "Open terminal", "T", ctrl: true, alt: false,
            shift: true, win: false, HotkeyAction.Run, "wt.exe",
            appliesToAllProfiles: true, createdAt, new FixedClock(now));

        entity.Id.Should().Be(id);
        entity.OwnerOid.Should().Be(ownerOid);
        entity.Description.Should().Be("Open terminal");
        entity.Key.Should().Be("T");
        entity.Ctrl.Should().BeTrue();
        entity.Shift.Should().BeTrue();
        entity.Action.Should().Be(HotkeyAction.Run);
        entity.Parameters.Should().Be("wt.exe");
        entity.AppliesToAllProfiles.Should().BeTrue();
        entity.CreatedAt.Should().Be(createdAt);
        entity.UpdatedAt.Should().Be(now);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Domain.Tests --filter "FullyQualifiedName~EntityHistoryTests|FullyQualifiedName~RestoreFactoryTests" -v minimal`
Expected: compile error — `EntityHistory`, `TrackedEntityType`, `HistoryChangeType`, `Restore` do not exist.

- [ ] **Step 3: Implement**

`src/Backend/AHKFlowApp.Domain/Enums/TrackedEntityType.cs`:

```csharp
namespace AHKFlowApp.Domain.Enums;

public enum TrackedEntityType
{
    Hotstring = 1,
    Hotkey = 2,
}
```

`src/Backend/AHKFlowApp.Domain/Enums/HistoryChangeType.cs`:

```csharp
namespace AHKFlowApp.Domain.Enums;

public enum HistoryChangeType
{
    Edit = 1,
    Delete = 2,
}
```

`src/Backend/AHKFlowApp.Domain/Entities/EntityHistory.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class EntityHistory
{
    private EntityHistory()
    {
        SnapshotJson = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public TrackedEntityType EntityType { get; private set; }
    public Guid EntityId { get; private set; }
    public int Version { get; private set; }
    public HistoryChangeType ChangeType { get; private set; }
    public int SchemaVersion { get; private set; }
    public DateTimeOffset CapturedAt { get; private set; }
    public string SnapshotJson { get; private set; }

    public static EntityHistory Create(
        Guid ownerOid,
        TrackedEntityType entityType,
        Guid entityId,
        int version,
        HistoryChangeType changeType,
        int schemaVersion,
        string snapshotJson,
        TimeProvider clock)
        => new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            EntityType = entityType,
            EntityId = entityId,
            Version = version,
            ChangeType = changeType,
            SchemaVersion = schemaVersion,
            SnapshotJson = snapshotJson,
            CapturedAt = clock.GetUtcNow(),
        };

    // A concurrent writer may have claimed the same version; the retry path re-reads
    // the max and re-assigns before saving again.
    public void ReassignVersion(int version) => Version = version;
}
```

Add to `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` (after `Create`, before `Update`):

```csharp
    public static Hotstring Restore(
        Guid id,
        Guid ownerOid,
        string trigger,
        string replacement,
        string? description,
        bool appliesToAllProfiles,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        DateTimeOffset createdAt,
        TimeProvider clock)
        => new()
        {
            Id = id,
            OwnerOid = ownerOid,
            Trigger = trigger,
            Replacement = replacement,
            Description = description,
            AppliesToAllProfiles = appliesToAllProfiles,
            IsEndingCharacterRequired = isEndingCharacterRequired,
            IsTriggerInsideWord = isTriggerInsideWord,
            CreatedAt = createdAt,
            UpdatedAt = clock.GetUtcNow(),
        };
```

Add to `src/Backend/AHKFlowApp.Domain/Entities/Hotkey.cs` (after `Create`, before `Update`):

```csharp
    public static Hotkey Restore(
        Guid id,
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
        DateTimeOffset createdAt,
        TimeProvider clock)
        => new()
        {
            Id = id,
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
            CreatedAt = createdAt,
            UpdatedAt = clock.GetUtcNow(),
        };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Domain.Tests --filter "FullyQualifiedName~EntityHistoryTests|FullyQualifiedName~RestoreFactoryTests" -v minimal`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Domain tests/AHKFlowApp.Domain.Tests
git commit -m "feat: add EntityHistory entity + Restore factories"
```

---

### Task 2: Persistence — DbSet, EF configuration, migration

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`
- Create: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/EntityHistoryConfiguration.cs`
- Create (generated): `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_AddEntityHistory.cs`

**Interfaces:**
- Consumes: `EntityHistory` from Task 1.
- Produces: `IAppDbContext.EntityHistories` (`DbSet<EntityHistory>`); table `EntityHistories` with unique index `IX_EntityHistory_Owner_Type_Entity_Version` on `(OwnerOid, EntityType, EntityId, Version)`.

No new unit test here — the schema is exercised by every integration test from Task 3 onward (fixtures run `Database.MigrateAsync()`), and Task 3 includes an explicit unique-index test.

- [ ] **Step 1: Add the DbSet to both context surfaces**

In `IAppDbContext.cs`, after `DbSet<HotkeyCategory> HotkeyCategories { get; }`:

```csharp
    DbSet<EntityHistory> EntityHistories { get; }
```

In `AppDbContext.cs`, after the `HotkeyCategories` property:

```csharp
    public DbSet<EntityHistory> EntityHistories => Set<EntityHistory>();
```

- [ ] **Step 2: Write the configuration**

`src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/EntityHistoryConfiguration.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class EntityHistoryConfiguration : IEntityTypeConfiguration<EntityHistory>
{
    public void Configure(EntityTypeBuilder<EntityHistory> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.Property(x => x.EntityType).IsRequired();
        builder.Property(x => x.EntityId).IsRequired();
        builder.Property(x => x.Version).IsRequired();
        builder.Property(x => x.ChangeType).IsRequired();
        builder.Property(x => x.SchemaVersion).IsRequired();
        builder.Property(x => x.CapturedAt).IsRequired();
        builder.Property(x => x.SnapshotJson).IsRequired();

        // Unique: guarantees history/{version} is unambiguous under concurrent writes.
        builder.HasIndex(x => new { x.OwnerOid, x.EntityType, x.EntityId, x.Version })
            .IsUnique()
            .HasDatabaseName("IX_EntityHistory_Owner_Type_Entity_Version");
    }
}
```

- [ ] **Step 3: Generate the migration**

Run:

```bash
dotnet ef migrations add AddEntityHistory --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Expected: new `<timestamp>_AddEntityHistory.cs` + `.Designer.cs`; updated `AppDbContextModelSnapshot.cs`. Inspect `Up()`: **only** `CreateTable("EntityHistories", ...)` + `CreateIndex` with `unique: true` — no changes to existing tables. If existing tables are touched, stop and investigate before committing.

- [ ] **Step 4: Build + run existing integration tests to prove the migration applies**

Run: `dotnet build`
Expected: success.

Run: `dotnet test tests/AHKFlowApp.Infrastructure.Tests -v minimal`
Expected: PASS (fixtures apply all migrations including the new one).

- [ ] **Step 5: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs src/Backend/AHKFlowApp.Infrastructure
git commit -m "feat: add EntityHistories table + unique version index"
```

---

### Task 3: Application — snapshot DTOs, recorder, save-retry helper, DI

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/HistorySnapshots.cs`
- Create: `src/Backend/AHKFlowApp.Application/Abstractions/IEntityHistoryRecorder.cs`
- Create: `src/Backend/AHKFlowApp.Application/Services/EntityHistoryRecorder.cs`
- Create: `src/Backend/AHKFlowApp.Application/Common/HistorySaveRetry.cs`
- Modify: `src/Backend/AHKFlowApp.Application/DependencyInjection.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/HistoryDbFixture.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/CurrentUserHelper.cs` (copy of the Hotstrings one, new namespace)
- Test: `tests/AHKFlowApp.Application.Tests/History/FixedClock.cs` (copy of the Hotstrings one, new namespace)
- Test: `tests/AHKFlowApp.Application.Tests/History/EntityHistoryRecorderTests.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/HistorySaveRetryTests.cs`

**Interfaces:**
- Consumes: `EntityHistory`, enums (Task 1), `EntityHistories` DbSet (Task 2), existing `IsDuplicateKeyViolation()`.
- Produces (used by Tasks 4–10):
  - `public sealed record HotstringSnapshot(string Trigger, string Replacement, string? Description, bool AppliesToAllProfiles, bool IsEndingCharacterRequired, bool IsTriggerInsideWord, Guid[] ProfileIds, Guid[] CategoryIds, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)`
  - `public sealed record HotkeySnapshot(string Description, string Key, bool Ctrl, bool Alt, bool Shift, bool Win, HotkeyAction Action, string Parameters, bool AppliesToAllProfiles, Guid[] ProfileIds, Guid[] CategoryIds, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)`
  - `IEntityHistoryRecorder.RecordHotstringAsync(Hotstring entity, HistoryChangeType changeType, CancellationToken ct)` → `Task<EntityHistory>` (and `RecordHotkeyAsync` twin). Adds the row to the tracked context; **does not save**.
  - `db.SaveWithHistoryRetryAsync(EntityHistory entry, CancellationToken ct)` and `db.SaveWithHistoryRetryAsync(IReadOnlyList<EntityHistory> entries, CancellationToken ct)` extension methods.
  - `ex.IsHistoryVersionConflict()` extension on `DbUpdateException`.
  - Constants: `EntityHistoryRecorder.MaxVersionsPerItem = 50`, `EntityHistoryRecorder.CurrentSchemaVersion = 1`.

- [ ] **Step 1: Create the test scaffolding**

`tests/AHKFlowApp.Application.Tests/History/HistoryDbFixture.cs`:

```csharp
using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

public sealed class HistoryDbFixture : MigratedDbFixture;

[CollectionDefinition("HistoryDb")]
public sealed class HistoryDbCollection : ICollectionFixture<HistoryDbFixture>;
```

`tests/AHKFlowApp.Application.Tests/History/CurrentUserHelper.cs` — same body as `tests/AHKFlowApp.Application.Tests/Hotstrings/CurrentUserHelper.cs` with namespace `AHKFlowApp.Application.Tests.History`:

```csharp
using AHKFlowApp.Application.Abstractions;
using NSubstitute;

namespace AHKFlowApp.Application.Tests.History;

internal static class CurrentUserHelper
{
    public static ICurrentUser For(Guid? oid)
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(oid);
        return u;
    }
}
```

`tests/AHKFlowApp.Application.Tests/History/FixedClock.cs`:

```csharp
namespace AHKFlowApp.Application.Tests.History;

internal sealed class FixedClock(DateTimeOffset now) : TimeProvider
{
    private DateTimeOffset _now = now;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan delta) => _now = _now.Add(delta);
}
```

- [ ] **Step 2: Write the failing recorder tests**

`tests/AHKFlowApp.Application.Tests/History/EntityHistoryRecorderTests.cs`:

```csharp
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class EntityHistoryRecorderTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task RecordHotstringAsync_FirstRecord_WritesVersion1WithFullSnapshot()
    {
        var owner = Guid.NewGuid();
        var profileId = Guid.NewGuid();
        var categoryId = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("rec1").WithReplacement("body")
            .WithProfiles(profileId).WithCategory(categoryId)
            .Build();

        await using AppDbContext db = fx.CreateContext();
        db.Hotstrings.Add(entity);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);
        // Junction FKs would fail the save (profile/category rows don't exist) — assert on the tracked entry.

        entry.OwnerOid.Should().Be(owner);
        entry.EntityType.Should().Be(TrackedEntityType.Hotstring);
        entry.EntityId.Should().Be(entity.Id);
        entry.Version.Should().Be(1);
        entry.ChangeType.Should().Be(HistoryChangeType.Edit);
        entry.SchemaVersion.Should().Be(EntityHistoryRecorder.CurrentSchemaVersion);

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(entry.SnapshotJson);
        snapshot!.Trigger.Should().Be("rec1");
        snapshot.Replacement.Should().Be("body");
        snapshot.AppliesToAllProfiles.Should().BeFalse();
        snapshot.ProfileIds.Should().ContainSingle().Which.Should().Be(profileId);
        snapshot.CategoryIds.Should().ContainSingle().Which.Should().Be(categoryId);
    }

    [Fact]
    public async Task RecordHotstringAsync_SecondRecord_IncrementsVersion()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rec2").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            EntityHistoryRecorder seedRecorder = new(seed, TimeProvider.System);
            await seedRecorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Hotstring reloaded = await db.Hotstrings.SingleAsync(h => h.Id == entity.Id);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotstringAsync(reloaded, HistoryChangeType.Edit, default);

        entry.Version.Should().Be(2);
    }

    [Fact]
    public async Task RecordHotstringAsync_At50Rows_PrunesOldestSoCapHolds()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rec3").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            for (int v = 1; v <= 50; v++)
            {
                seed.EntityHistories.Add(EntityHistory.Create(
                    owner, TrackedEntityType.Hotstring, entity.Id, v,
                    HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Hotstring reloaded = await db.Hotstrings.SingleAsync(h => h.Id == entity.Id);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        await recorder.RecordHotstringAsync(reloaded, HistoryChangeType.Edit, default);
        await db.SaveChangesAsync();

        List<int> versions = await db.EntityHistories
            .Where(h => h.EntityId == entity.Id)
            .Select(h => h.Version)
            .OrderBy(v => v)
            .ToListAsync();
        versions.Should().HaveCount(50);
        versions.First().Should().Be(2);   // v1 pruned
        versions.Last().Should().Be(51);   // newest retained
    }

    [Fact]
    public async Task RecordHotkeyAsync_WritesHotkeySnapshotWithModifiersAndAction()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).Build();

        await using AppDbContext db = fx.CreateContext();
        db.Hotkeys.Add(entity);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Delete, default);

        entry.EntityType.Should().Be(TrackedEntityType.Hotkey);
        entry.ChangeType.Should().Be(HistoryChangeType.Delete);
        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(entry.SnapshotJson);
        snapshot!.Key.Should().Be(entity.Key);
        snapshot.Action.Should().Be(entity.Action);
        snapshot.CreatedAt.Should().Be(entity.CreatedAt);
    }

    [Fact]
    public async Task UniqueIndex_DuplicateVersionForSameEntity_Throws()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        db.EntityHistories.Add(EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
        await db.SaveChangesAsync();

        db.EntityHistories.Add(EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
        Func<Task> act = () => db.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }
}
```

Note: check `tests/AHKFlowApp.TestUtilities/Builders/HotkeyBuilder.cs` for the exact builder methods before using it — mirror how `HotkeyBuilder` is used in `tests/AHKFlowApp.Application.Tests/Hotkeys/UpdateHotkeyCommandHandlerTests.cs` if `WithOwner` differs.

- [ ] **Step 3: Write the failing save-retry tests**

`tests/AHKFlowApp.Application.Tests/History/HistorySaveRetryTests.cs`:

```csharp
using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class HistorySaveRetryTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task SaveWithHistoryRetryAsync_VersionCollision_BumpsVersionAndSaves()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        // Our context stages version 1…
        await using AppDbContext db = fx.CreateContext();
        EntityHistory entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        // …but a "concurrent writer" commits version 1 first.
        await using (AppDbContext rival = fx.CreateContext())
        {
            rival.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await rival.SaveChangesAsync();
        }

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(2);
        (await db.EntityHistories.CountAsync(h => h.EntityId == entityId)).Should().Be(2);
    }

    [Fact]
    public async Task SaveWithHistoryRetryAsync_NoCollision_SavesNormally()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        EntityHistory entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(1);
    }
}
```

Note: `HistorySaveRetry` and `IsDuplicateKeyViolation` are `internal` to Application. `AssemblyInfo.cs` in the test project — verify `InternalsVisibleTo` is already granted (Application.Tests already constructs `internal` handlers, so it is); if not, add it.

- [ ] **Step 4: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~EntityHistoryRecorderTests|FullyQualifiedName~HistorySaveRetryTests" -v minimal`
Expected: compile error — `HotstringSnapshot`, `EntityHistoryRecorder`, `SaveWithHistoryRetryAsync` do not exist.

- [ ] **Step 5: Implement**

`src/Backend/AHKFlowApp.Application/DTOs/HistorySnapshots.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>Point-in-time snapshot of a hotstring aggregate, stored as history JSON (schema v1).</summary>
/// <param name="Trigger">Abbreviation that activated the replacement.</param>
/// <param name="Replacement">Text that replaced the trigger.</param>
/// <param name="Description">Optional human-readable note.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applied to every profile.</param>
/// <param name="IsEndingCharacterRequired">AutoHotkey ending-character option at capture time.</param>
/// <param name="IsTriggerInsideWord">AutoHotkey inside-word option at capture time.</param>
/// <param name="ProfileIds">Profile links at capture time.</param>
/// <param name="CategoryIds">Category links at capture time.</param>
/// <param name="CreatedAt">Original creation timestamp.</param>
/// <param name="UpdatedAt">Last-update timestamp at capture time.</param>
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
    DateTimeOffset UpdatedAt);

/// <summary>Point-in-time snapshot of a hotkey aggregate, stored as history JSON (schema v1).</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific parameter payload.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applied to every profile.</param>
/// <param name="ProfileIds">Profile links at capture time.</param>
/// <param name="CategoryIds">Category links at capture time.</param>
/// <param name="CreatedAt">Original creation timestamp.</param>
/// <param name="UpdatedAt">Last-update timestamp at capture time.</param>
public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
```

`src/Backend/AHKFlowApp.Application/Abstractions/IEntityHistoryRecorder.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Abstractions;

public interface IEntityHistoryRecorder
{
    /// <summary>Stages a before-image of the aggregate on the tracked context. Caller owns SaveChanges.</summary>
    Task<EntityHistory> RecordHotstringAsync(Hotstring entity, HistoryChangeType changeType, CancellationToken ct);

    /// <summary>Stages a before-image of the aggregate on the tracked context. Caller owns SaveChanges.</summary>
    Task<EntityHistory> RecordHotkeyAsync(Hotkey entity, HistoryChangeType changeType, CancellationToken ct);
}
```

`src/Backend/AHKFlowApp.Application/Services/EntityHistoryRecorder.cs`:

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Services;

internal sealed class EntityHistoryRecorder(IAppDbContext db, TimeProvider clock) : IEntityHistoryRecorder
{
    internal const int MaxVersionsPerItem = 50;
    internal const int CurrentSchemaVersion = 1;

    public Task<EntityHistory> RecordHotstringAsync(Hotstring entity, HistoryChangeType changeType, CancellationToken ct)
    {
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
            entity.UpdatedAt);

        return RecordAsync(
            entity.OwnerOid, TrackedEntityType.Hotstring, entity.Id, changeType,
            JsonSerializer.Serialize(snapshot), ct);
    }

    public Task<EntityHistory> RecordHotkeyAsync(Hotkey entity, HistoryChangeType changeType, CancellationToken ct)
    {
        HotkeySnapshot snapshot = new(
            entity.Description,
            entity.Key,
            entity.Ctrl,
            entity.Alt,
            entity.Shift,
            entity.Win,
            entity.Action,
            entity.Parameters,
            entity.AppliesToAllProfiles,
            [.. entity.Profiles.Select(p => p.ProfileId)],
            [.. entity.Categories.Select(c => c.CategoryId)],
            entity.CreatedAt,
            entity.UpdatedAt);

        return RecordAsync(
            entity.OwnerOid, TrackedEntityType.Hotkey, entity.Id, changeType,
            JsonSerializer.Serialize(snapshot), ct);
    }

    private async Task<EntityHistory> RecordAsync(
        Guid ownerOid,
        TrackedEntityType entityType,
        Guid entityId,
        HistoryChangeType changeType,
        string snapshotJson,
        CancellationToken ct)
    {
        List<EntityHistory> existing = await db.EntityHistories
            .Where(h => h.EntityType == entityType && h.EntityId == entityId)
            .OrderBy(h => h.Version)
            .ToListAsync(ct);

        int nextVersion = (existing.Count > 0 ? existing[^1].Version : 0) + 1;

        var entry = EntityHistory.Create(
            ownerOid, entityType, entityId, nextVersion, changeType,
            CurrentSchemaVersion, snapshotJson, clock);
        db.EntityHistories.Add(entry);

        int excess = existing.Count + 1 - MaxVersionsPerItem;
        if (excess > 0)
            db.EntityHistories.RemoveRange(existing.Take(excess));

        return entry;
    }
}
```

`src/Backend/AHKFlowApp.Application/Common/HistorySaveRetry.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Common;

internal static class HistorySaveRetry
{
    private const string HistoryVersionIndexName = "IX_EntityHistory_Owner_Type_Entity_Version";

    internal static bool IsHistoryVersionConflict(this DbUpdateException ex) =>
        ex.IsDuplicateKeyViolation() &&
        ex.InnerException?.Message.Contains(HistoryVersionIndexName) == true;

    internal static Task SaveWithHistoryRetryAsync(
        this IAppDbContext db, EntityHistory entry, CancellationToken ct) =>
        db.SaveWithHistoryRetryAsync([entry], ct);

    /// <summary>
    /// Saves changes; if a concurrent writer claimed the same history version, re-reads
    /// the max committed version per entry, re-assigns, and saves once more. A second
    /// collision propagates as DbUpdateException for the handler to map to Conflict.
    /// </summary>
    internal static async Task SaveWithHistoryRetryAsync(
        this IAppDbContext db, IReadOnlyList<EntityHistory> entries, CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsHistoryVersionConflict())
        {
            foreach (EntityHistory entry in entries)
            {
                int max = await db.EntityHistories
                    .Where(h => h.EntityType == entry.EntityType && h.EntityId == entry.EntityId)
                    .MaxAsync(h => (int?)h.Version, ct) ?? 0;
                if (max >= entry.Version)
                    entry.ReassignVersion(max + 1);
            }

            await db.SaveChangesAsync(ct);
        }
    }
}
```

Register in `src/Backend/AHKFlowApp.Application/DependencyInjection.cs` (after `AddScoped<ProfileScriptLoader>()`; add `using AHKFlowApp.Application.Abstractions;`):

```csharp
        services.AddScoped<IEntityHistoryRecorder, EntityHistoryRecorder>();
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~EntityHistoryRecorderTests|FullyQualifiedName~HistorySaveRetryTests" -v minimal`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests/History
git commit -m "feat: history recorder + snapshots + version-collision retry"
```

---

### Task 4: Wire capture into Update handlers (hotstring + hotkey)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/UpdateHotkeyCommand.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/UpdateCaptureTests.cs`

**Interfaces:**
- Consumes: `IEntityHistoryRecorder`, `SaveWithHistoryRetryAsync`, `IsHistoryVersionConflict` (Task 3).
- Produces: every successful update writes one `Edit` before-image capturing the **pre-update** state.

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Application.Tests/History/UpdateCaptureTests.cs`:

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class UpdateCaptureTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task UpdateHotstring_WritesBeforeImageOfPreviousState()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("cap1").WithReplacement("original").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        UpdateHotstringCommand cmd = new(entity.Id,
            new UpdateHotstringDto("cap1", "changed", null, true, true, true, null));

        var result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        EntityHistory entry = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotstring);
        entry.Version.Should().Be(1);
        entry.ChangeType.Should().Be(HistoryChangeType.Edit);
        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(entry.SnapshotJson);
        snapshot!.Replacement.Should().Be("original"); // before-image, not the new state
    }

    [Fact]
    public async Task UpdateHotstring_TwoUpdates_ProducesVersions1And2()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("cap2").WithReplacement("v0").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        foreach (string replacement in new[] { "v1", "v2" })
        {
            await using AppDbContext db = fx.CreateContext();
            UpdateHotstringCommandHandler handler = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
            var result = await handler.Handle(
                new UpdateHotstringCommand(entity.Id,
                    new UpdateHotstringDto("cap2", replacement, null, true, true, true, null)), default);
            result.IsSuccess.Should().BeTrue();
        }

        await using AppDbContext verify = fx.CreateContext();
        List<int> versions = await verify.EntityHistories
            .Where(h => h.EntityId == entity.Id)
            .Select(h => h.Version).OrderBy(v => v).ToListAsync();
        versions.Should().Equal(1, 2);
    }

    [Fact]
    public async Task UpdateHotkey_WritesBeforeImageOfPreviousState()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).Build();
        string originalKey = entity.Key;

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new AHKFlowApp.Application.Commands.Hotkeys.UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        var cmd = new AHKFlowApp.Application.Commands.Hotkeys.UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("changed desc", "F9", false, false, false, false,
                entity.Action, entity.Parameters, null, true, null));

        var result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        EntityHistory entry = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotkey);
        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(entry.SnapshotJson);
        snapshot!.Key.Should().Be(originalKey);
    }
}
```

Adjust `HotkeyBuilder` usage and `UpdateHotkeyDto` argument order to the real signatures if they differ — check the builder and DTO first.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~UpdateCaptureTests" -v minimal`
Expected: compile error — handlers don't take an `IEntityHistoryRecorder` parameter yet.

- [ ] **Step 3: Implement — UpdateHotstringCommand.cs**

Change the handler's primary constructor and save call:

```csharp
internal sealed class UpdateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IRequestHandler<UpdateHotstringCommand, Result<HotstringDto>>
```

Immediately after the category-validation block and **before** `entity.Update(...)`, add:

```csharp
        EntityHistory historyEntry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, ct);
```

Replace the save block at the end:

```csharp
        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict("A hotstring with this trigger already exists.");
        }
```

Add usings: `AHKFlowApp.Domain.Enums` (for `HistoryChangeType`); `AHKFlowApp.Application.Common` and `AHKFlowApp.Application.Abstractions` are already imported.

- [ ] **Step 4: Implement — UpdateHotkeyCommand.cs**

Same shape: add `IEntityHistoryRecorder recorder` as 4th constructor parameter; before `entity.Update(...)`:

```csharp
        EntityHistory historyEntry = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Edit, ct);
```

Replace the save block:

```csharp
        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }
```

- [ ] **Step 5: Run new + existing tests**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~UpdateCaptureTests|FullyQualifiedName~UpdateHotstringCommandHandlerTests|FullyQualifiedName~UpdateHotkeyCommandHandlerTests" -v minimal`
Expected: PASS — existing update tests construct the handler; they will need the new 4th argument (`new EntityHistoryRecorder(db, TimeProvider.System)`). Update those constructor calls as part of this task.

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: capture before-images on hotstring/hotkey update"
```

---

### Task 5: Wire capture into Delete + BulkDelete handlers (with Includes)

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/DeleteHotstringCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/BulkDeleteHotstringsCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/DeleteHotkeyCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/BulkDeleteHotkeysCommand.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/DeleteCaptureTests.cs`

**Interfaces:**
- Consumes: Task 3 recorder + retry helper.
- Produces: every delete writes a `Delete` tombstone whose snapshot includes `ProfileIds`/`CategoryIds`; row is hard-deleted as before.

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Application.Tests/History/DeleteCaptureTests.cs`:

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class DeleteCaptureTests(HistoryDbFixture fx)
{
    private async Task<(Guid Owner, Hotstring Entity, Guid ProfileId, Guid CategoryId)> SeedLinkedHotstringAsync(string trigger)
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger(trigger)
            .WithProfiles(profile.Id).WithCategory(category.Id)
            .Build();

        await using AppDbContext seed = fx.CreateContext();
        seed.Profiles.Add(profile);
        seed.Categories.Add(category);
        seed.Hotstrings.Add(entity);
        await seed.SaveChangesAsync();
        return (owner, entity, profile.Id, category.Id);
    }

    [Fact]
    public async Task DeleteHotstring_WritesTombstoneIncludingLinks_AndRemovesRow()
    {
        (Guid owner, Hotstring entity, Guid profileId, Guid categoryId) = await SeedLinkedHotstringAsync("del1");

        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        var result = await handler.Handle(new DeleteHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        (await db.Hotstrings.AnyAsync(h => h.Id == entity.Id)).Should().BeFalse();

        EntityHistory tombstone = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotstring);
        tombstone.ChangeType.Should().Be(HistoryChangeType.Delete);
        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(tombstone.SnapshotJson);
        snapshot!.ProfileIds.Should().ContainSingle().Which.Should().Be(profileId);
        snapshot.CategoryIds.Should().ContainSingle().Which.Should().Be(categoryId);
    }

    [Fact]
    public async Task BulkDeleteHotstrings_WritesOneTombstonePerDeletedRow()
    {
        var owner = Guid.NewGuid();
        Hotstring first = new HotstringBuilder().WithOwner(owner).WithTrigger("bulk1").Build();
        Hotstring second = new HotstringBuilder().WithOwner(owner).WithTrigger("bulk2").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        BulkDeleteHotstringsCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        var result = await handler.Handle(
            new BulkDeleteHotstringsCommand(new BulkDeleteRequestDto([first.Id, second.Id])), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.DeletedCount.Should().Be(2);
        List<EntityHistory> tombstones = await db.EntityHistories
            .Where(h => h.EntityId == first.Id || h.EntityId == second.Id)
            .ToListAsync();
        tombstones.Should().HaveCount(2);
        tombstones.Should().OnlyContain(t => t.ChangeType == HistoryChangeType.Delete);
    }

    [Fact]
    public async Task DeleteHotkey_WritesTombstone()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new AHKFlowApp.Application.Commands.Hotkeys.DeleteHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        var result = await handler.Handle(
            new AHKFlowApp.Application.Commands.Hotkeys.DeleteHotkeyCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        EntityHistory tombstone = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotkey);
        tombstone.ChangeType.Should().Be(HistoryChangeType.Delete);
    }
}
```

Check `ProfileBuilder`/`CategoryBuilder`/`BulkDeleteRequestDto` exact shapes before writing — adjust construction to their real APIs.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~DeleteCaptureTests" -v minimal`
Expected: compile error — delete handlers don't take a recorder yet.

- [ ] **Step 3: Implement — DeleteHotstringCommand.cs**

```csharp
internal sealed class DeleteHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    IEntityHistoryRecorder recorder)
    : IRequestHandler<DeleteHotstringCommand, Result>
{
    public async Task<Result> Handle(DeleteHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        EntityHistory tombstone = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Delete, ct);
        db.Hotstrings.Remove(entity);
        await db.SaveWithHistoryRetryAsync(tombstone, ct);

        return Result.Success();
    }
}
```

Add usings: `AHKFlowApp.Application.Common`, `AHKFlowApp.Domain.Enums`.

- [ ] **Step 4: Implement — BulkDeleteHotstringsCommand.cs**

Add `IEntityHistoryRecorder recorder` as 3rd constructor parameter; add `.Include(h => h.Profiles).Include(h => h.Categories)` to the `ownedRows` query; replace the delete block:

```csharp
        if (ownedRows.Count > 0)
        {
            List<EntityHistory> tombstones = [];
            foreach (Hotstring row in ownedRows)
                tombstones.Add(await recorder.RecordHotstringAsync(row, HistoryChangeType.Delete, ct));

            db.Hotstrings.RemoveRange(ownedRows);
            await db.SaveWithHistoryRetryAsync(tombstones, ct);
        }
```

- [ ] **Step 5: Implement the hotkey twins**

`DeleteHotkeyCommand.cs` and `BulkDeleteHotkeysCommand.cs`: identical shape — add `IEntityHistoryRecorder recorder` parameter, add the two `Include`s to the entity query, call `recorder.RecordHotkeyAsync(entity, HistoryChangeType.Delete, ct)` before `Remove`/`RemoveRange`, save via `SaveWithHistoryRetryAsync`.

- [ ] **Step 6: Run new + existing delete tests**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~DeleteCaptureTests|FullyQualifiedName~DeleteHotstringCommandHandlerTests|FullyQualifiedName~DeleteHotkeyCommandHandlerTests" -v minimal`
Expected: PASS. Existing delete-handler tests need the new constructor argument — update them in this task.

- [ ] **Step 7: Commit**

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: write delete tombstones w/ profile+category links"
```

---

### Task 6: History DTOs + list/version queries (both entities)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/HistoryDtos.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringHistoryQuery.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringHistoryVersionQuery.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyHistoryQuery.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyHistoryVersionQuery.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/HistoryQueryTests.cs`

**Interfaces:**
- Consumes: Tasks 1–3 types.
- Produces (used by controllers and frontend):
  - `public sealed record HistoryEntryDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt)`
  - `public sealed record HotstringHistoryVersionDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt, HotstringSnapshot Snapshot)`
  - `public sealed record HotkeyHistoryVersionDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt, HotkeySnapshot Snapshot)`
  - `public sealed record DeletedHotstringDto(Guid Id, string Trigger, string Replacement, string? Description, DateTimeOffset DeletedAt)`
  - `public sealed record DeletedHotkeyDto(Guid Id, string Description, string Key, bool Ctrl, bool Alt, bool Shift, bool Win, DateTimeOffset DeletedAt)`
  - `GetHotstringHistoryQuery(Guid Id)` → `Result<HistoryEntryDto[]>` (newest first; empty array for a live item with no history; `NotFound` when neither live row nor history exists for this owner)
  - `GetHotstringHistoryVersionQuery(Guid Id, int Version)` → `Result<HotstringHistoryVersionDto>`
  - `GetHotkeyHistoryQuery` / `GetHotkeyHistoryVersionQuery` twins.

- [ ] **Step 1: Write the DTOs** (all XML-doc'd — the coverage test enforces it)

`src/Backend/AHKFlowApp.Application/DTOs/HistoryDtos.cs`:

```csharp
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>One saved version of a tracked item.</summary>
/// <param name="Version">Monotonic 1-based version number.</param>
/// <param name="ChangeType">Whether this before-image was captured by an edit or a delete.</param>
/// <param name="CapturedAt">UTC timestamp of the change that produced this version.</param>
public sealed record HistoryEntryDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt);

/// <summary>Full saved version of a hotstring, including its snapshot for preview.</summary>
/// <param name="Version">Monotonic 1-based version number.</param>
/// <param name="ChangeType">Whether this before-image was captured by an edit or a delete.</param>
/// <param name="CapturedAt">UTC timestamp of the change that produced this version.</param>
/// <param name="Snapshot">The hotstring state at capture time.</param>
public sealed record HotstringHistoryVersionDto(
    int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt, HotstringSnapshot Snapshot);

/// <summary>Full saved version of a hotkey, including its snapshot for preview.</summary>
/// <param name="Version">Monotonic 1-based version number.</param>
/// <param name="ChangeType">Whether this before-image was captured by an edit or a delete.</param>
/// <param name="CapturedAt">UTC timestamp of the change that produced this version.</param>
/// <param name="Snapshot">The hotkey state at capture time.</param>
public sealed record HotkeyHistoryVersionDto(
    int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt, HotkeySnapshot Snapshot);

/// <summary>A deleted hotstring shown in the Recycle Bin.</summary>
/// <param name="Id">The original hotstring id (restore keeps it).</param>
/// <param name="Trigger">Trigger at deletion time.</param>
/// <param name="Replacement">Replacement at deletion time.</param>
/// <param name="Description">Description at deletion time.</param>
/// <param name="DeletedAt">UTC timestamp of the deletion.</param>
public sealed record DeletedHotstringDto(
    Guid Id, string Trigger, string Replacement, string? Description, DateTimeOffset DeletedAt);

/// <summary>A deleted hotkey shown in the Recycle Bin.</summary>
/// <param name="Id">The original hotkey id (restore keeps it).</param>
/// <param name="Description">Description at deletion time.</param>
/// <param name="Key">Main key at deletion time.</param>
/// <param name="Ctrl">Ctrl modifier.</param>
/// <param name="Alt">Alt modifier.</param>
/// <param name="Shift">Shift modifier.</param>
/// <param name="Win">Windows modifier.</param>
/// <param name="DeletedAt">UTC timestamp of the deletion.</param>
public sealed record DeletedHotkeyDto(
    Guid Id, string Description, string Key, bool Ctrl, bool Alt, bool Shift, bool Win, DateTimeOffset DeletedAt);
```

- [ ] **Step 2: Write the failing query tests**

`tests/AHKFlowApp.Application.Tests/History/HistoryQueryTests.cs`:

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
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
public sealed class HistoryQueryTests(HistoryDbFixture fx)
{
    private async Task<(Guid Owner, Hotstring Entity)> SeedWithOneEditAsync(string trigger)
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger(trigger).Build();

        await using AppDbContext seed = fx.CreateContext();
        seed.Hotstrings.Add(entity);
        EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
        await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);
        await seed.SaveChangesAsync();
        return (owner, entity);
    }

    [Fact]
    public async Task GetHistory_ReturnsEntriesNewestFirst()
    {
        (Guid owner, Hotstring entity) = await SeedWithOneEditAsync("hq1");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HistoryEntryDto[]> result = await handler.Handle(new GetHotstringHistoryQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        result.Value[0].Version.Should().Be(1);
        result.Value[0].ChangeType.Should().Be(HistoryChangeType.Edit);
    }

    [Fact]
    public async Task GetHistory_LiveItemWithNoHistory_ReturnsEmptyList()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("hq2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HistoryEntryDto[]> result = await handler.Handle(new GetHotstringHistoryQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task GetHistory_OtherUsersItem_ReturnsNotFound()
    {
        (Guid _, Hotstring entity) = await SeedWithOneEditAsync("hq3");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryQueryHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result<HistoryEntryDto[]> result = await handler.Handle(new GetHotstringHistoryQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task GetHistoryVersion_ReturnsDeserializedSnapshot()
    {
        (Guid owner, Hotstring entity) = await SeedWithOneEditAsync("hq4");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryVersionQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringHistoryVersionDto> result =
            await handler.Handle(new GetHotstringHistoryVersionQuery(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Snapshot.Trigger.Should().Be("hq4");
    }

    [Fact]
    public async Task GetHistoryVersion_UnknownVersion_ReturnsNotFound()
    {
        (Guid owner, Hotstring entity) = await SeedWithOneEditAsync("hq5");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryVersionQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringHistoryVersionDto> result =
            await handler.Handle(new GetHotstringHistoryVersionQuery(entity.Id, 99), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HistoryQueryTests" -v minimal`
Expected: compile error — queries do not exist.

- [ ] **Step 4: Implement the hotstring queries**

`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringHistoryQuery.cs`:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringHistoryQuery(Guid Id) : IRequest<Result<HistoryEntryDto[]>>;

internal sealed class GetHotstringHistoryQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetHotstringHistoryQuery, Result<HistoryEntryDto[]>>
{
    public async Task<Result<HistoryEntryDto[]>> Handle(GetHotstringHistoryQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        HistoryEntryDto[] entries = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id)
            .OrderByDescending(h => h.Version)
            .Select(h => new HistoryEntryDto(h.Version, h.ChangeType, h.CapturedAt))
            .ToArrayAsync(ct);

        if (entries.Length == 0)
        {
            bool liveExists = await db.Hotstrings
                .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
            if (!liveExists)
                return Result.NotFound();
        }

        return Result.Success(entries);
    }
}
```

`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringHistoryVersionQuery.cs`:

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringHistoryVersionQuery(Guid Id, int Version) : IRequest<Result<HotstringHistoryVersionDto>>;

internal sealed class GetHotstringHistoryVersionQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetHotstringHistoryVersionQuery, Result<HotstringHistoryVersionDto>>
{
    public async Task<Result<HotstringHistoryVersionDto>> Handle(
        GetHotstringHistoryVersionQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        EntityHistory? row = await db.EntityHistories
            .AsNoTracking()
            .FirstOrDefaultAsync(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id
                && h.Version == request.Version, ct);

        if (row is null)
            return Result.NotFound();

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(row.SnapshotJson);
        if (snapshot is null)
            return Result.Error("Snapshot could not be read.");

        return Result.Success(new HotstringHistoryVersionDto(row.Version, row.ChangeType, row.CapturedAt, snapshot));
    }
}
```

- [ ] **Step 5: Implement the hotkey twins**

`src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyHistoryQuery.cs` — identical to `GetHotstringHistoryQuery` with: namespace `AHKFlowApp.Application.Queries.Hotkeys`, record `GetHotkeyHistoryQuery`, `TrackedEntityType.Hotkey`, live check against `db.Hotkeys`.

`src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyHistoryVersionQuery.cs` — identical to `GetHotstringHistoryVersionQuery` with: record `GetHotkeyHistoryVersionQuery`, `TrackedEntityType.Hotkey`, `HotkeySnapshot`, `HotkeyHistoryVersionDto`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~HistoryQueryTests" -v minimal`
Expected: PASS (5 tests). Also run `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~ApplicationDtoXmlDocCoverageTests" -v minimal` — PASS (XML docs complete).

- [ ] **Step 7: Commit**

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: history list/version queries + DTOs"
```

---

### Task 7: Revert commands (both entities)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RevertHotstringCommand.cs`
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RevertHotkeyCommand.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/RevertCommandTests.cs`

**Interfaces:**
- Consumes: recorder, retry helper, snapshots, `HistoryChangeType`.
- Produces: `RevertHotstringCommand(Guid Id, int Version)` → `Result<HotstringDto>`; `RevertHotkeyCommand(Guid Id, int Version)` → `Result<HotkeyDto>`. Semantics: snapshot current as `Edit`, re-apply target snapshot via domain `Update`, rebuild junctions **keeping only links whose Profile/Category still exists** (missing links dropped silently; zero-profile outcome allowed), trigger collision → `Conflict`.

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Application.Tests/History/RevertCommandTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class RevertCommandTests(HistoryDbFixture fx)
{
    // Runs a real update through the handler so v1 (the before-image) exists.
    private async Task UpdateViaHandlerAsync(Guid owner, Guid id, UpdateHotstringDto dto)
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        (await handler.Handle(new UpdateHotstringCommand(id, dto), default)).IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Revert_RestoresFieldsAndLinks_AndWritesNewBeforeImage()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("rv1").WithReplacement("original")
            .WithProfiles(profile.Id).WithCategory(category.Id).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Categories.Add(category);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Edit away from the original (drops the links, changes replacement) -> v1 = original state.
        await UpdateViaHandlerAsync(owner, entity.Id,
            new UpdateHotstringDto("rv1", "changed", null, true, true, true, null));

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Replacement.Should().Be("original");
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);

        // The revert itself wrote a new before-image (v2 = the "changed" state).
        int versionCount = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versionCount.Should().Be(2);
    }

    [Fact]
    public async Task Revert_SnapshotProfileDeleted_DropsMissingLinkSilently()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("rv2").WithProfiles(profile.Id).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateViaHandlerAsync(owner, entity.Id,
            new UpdateHotstringDto("rv2", "by the way", null, true, true, true, null));

        // Delete the profile the snapshot references.
        await using (AppDbContext del = fx.CreateContext())
        {
            del.Profiles.Remove(await del.Profiles.SingleAsync(p => p.Id == profile.Id));
            await del.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(entity.Id, 1), default);

        // Succeeds with zero profile links (item inert until edited) — never fails on missing links.
        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task Revert_TriggerNowTakenByAnotherHotstring_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotstring victim = new HotstringBuilder().WithOwner(owner).WithTrigger("rv3-old").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(victim);
            await seed.SaveChangesAsync();
        }

        // v1 snapshot holds trigger "rv3-old"; rename to "rv3-new".
        await UpdateViaHandlerAsync(owner, victim.Id,
            new UpdateHotstringDto("rv3-new", "by the way", null, true, true, true, null));

        // Another hotstring claims the old trigger.
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder().WithOwner(owner).WithTrigger("rv3-old").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(victim.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Revert_UnknownVersion_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rv4").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(entity.Id, 9), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~RevertCommandTests" -v minimal`
Expected: compile error — `RevertHotstringCommand` does not exist.

- [ ] **Step 3: Implement — RevertHotstringCommand.cs**

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record RevertHotstringCommand(Guid Id, int Version) : IRequest<Result<HotstringDto>>;

internal sealed class RevertHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IRequestHandler<RevertHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(RevertHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        EntityHistory? row = await db.EntityHistories
            .AsNoTracking()
            .FirstOrDefaultAsync(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id
                && h.Version == request.Version, ct);

        if (row is null)
            return Result.NotFound();

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(row.SnapshotJson);
        if (snapshot is null)
            return Result.Error("Snapshot could not be read.");

        EntityHistory historyEntry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, ct);

        // Snapshot links may reference Profiles/Categories deleted since capture — keep only survivors.
        Guid[] liveProfileIds = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid && snapshot.ProfileIds.Contains(p.Id))
            .Select(p => p.Id)
            .ToArrayAsync(ct);
        Guid[] liveCategoryIds = await db.Categories
            .Where(c => c.OwnerOid == ownerOid && snapshot.CategoryIds.Contains(c.Id))
            .Select(c => c.Id)
            .ToArrayAsync(ct);

        entity.Update(
            snapshot.Trigger,
            snapshot.Replacement,
            snapshot.Description,
            snapshot.AppliesToAllProfiles,
            snapshot.IsEndingCharacterRequired,
            snapshot.IsTriggerInsideWord,
            clock);

        db.HotstringProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();
        if (!snapshot.AppliesToAllProfiles)
        {
            foreach (Guid pid in liveProfileIds)
            {
                var junction = HotstringProfile.Create(entity.Id, pid);
                db.HotstringProfiles.Add(junction);
                entity.Profiles.Add(junction);
            }
        }

        db.HotstringCategories.RemoveRange(entity.Categories);
        entity.Categories.Clear();
        foreach (Guid cid in liveCategoryIds)
        {
            var junction = HotstringCategory.Create(entity.Id, cid);
            db.HotstringCategories.Add(junction);
            entity.Categories.Add(junction);
        }

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict("A hotstring with this trigger already exists.");
        }

        return Result.Success(entity.ToDto());
    }
}
```

- [ ] **Step 4: Implement — RevertHotkeyCommand.cs**

Same structure with hotkey types: `RevertHotkeyCommand(Guid Id, int Version)` → `Result<HotkeyDto>`; load from `db.Hotkeys` with both `Include`s; `TrackedEntityType.Hotkey`; deserialize `HotkeySnapshot`; `recorder.RecordHotkeyAsync(entity, HistoryChangeType.Edit, ct)`; apply via `entity.Update(snapshot.Description, snapshot.Key, snapshot.Ctrl, snapshot.Alt, snapshot.Shift, snapshot.Win, snapshot.Action, snapshot.Parameters, snapshot.AppliesToAllProfiles, clock)`; rebuild `HotkeyProfile`/`HotkeyCategory` junctions from the filtered live ids; conflict message `"A hotkey with this key + modifier combination already exists."`; return `entity.ToDto()`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~RevertCommandTests" -v minimal`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: revert hotstring/hotkey to saved version"
```

---

### Task 8: Recycle Bin queries — ListDeleted (both entities)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListDeletedHotstringsQuery.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Hotkeys/ListDeletedHotkeysQuery.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/ListDeletedQueryTests.cs`

**Interfaces:**
- Consumes: tombstones written by Task 5; `DeletedHotstringDto`/`DeletedHotkeyDto` (Task 6).
- Produces: `ListDeletedHotstringsQuery()` → `Result<DeletedHotstringDto[]>`; `ListDeletedHotkeysQuery()` → `Result<DeletedHotkeyDto[]>`. A tombstone qualifies when: owner matches, `ChangeType == Delete`, it is the entity's **latest** history row, and no live row with that id exists. Newest deletion first.

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Application.Tests/History/ListDeletedQueryTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class ListDeletedQueryTests(HistoryDbFixture fx)
{
    private async Task<Hotstring> SeedAndDeleteAsync(Guid owner, string trigger)
    {
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger(trigger).Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        (await handler.Handle(new DeleteHotstringCommand(entity.Id), default)).IsSuccess.Should().BeTrue();
        return entity;
    }

    [Fact]
    public async Task ListDeleted_ReturnsTombstonedItemWithSnapshotFields()
    {
        var owner = Guid.NewGuid();
        Hotstring deleted = await SeedAndDeleteAsync(owner, "ld1");

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotstringDto[]> result = await handler.Handle(new ListDeletedHotstringsQuery(), default);

        result.IsSuccess.Should().BeTrue();
        DeletedHotstringDto dto = result.Value.Should().ContainSingle().Subject;
        dto.Id.Should().Be(deleted.Id);
        dto.Trigger.Should().Be("ld1");
        dto.Replacement.Should().Be(deleted.Replacement);
    }

    [Fact]
    public async Task ListDeleted_LiveItemsWithEditHistory_AreExcluded()
    {
        var owner = Guid.NewGuid();
        Hotstring live = new HotstringBuilder().WithOwner(owner).WithTrigger("ld2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(live);
            EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
            await recorder.RecordHotstringAsync(live, Domain.Enums.HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotstringDto[]> result = await handler.Handle(new ListDeletedHotstringsQuery(), default);

        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task ListDeleted_OtherOwnersTombstones_AreExcluded()
    {
        var owner = Guid.NewGuid();
        await SeedAndDeleteAsync(owner, "ld3");

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result<DeletedHotstringDto[]> result = await handler.Handle(new ListDeletedHotstringsQuery(), default);

        result.Value.Should().BeEmpty();
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~ListDeletedQueryTests" -v minimal`
Expected: compile error.

- [ ] **Step 3: Implement — ListDeletedHotstringsQuery.cs**

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record ListDeletedHotstringsQuery : IRequest<Result<DeletedHotstringDto[]>>;

internal sealed class ListDeletedHotstringsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<ListDeletedHotstringsQuery, Result<DeletedHotstringDto[]>>
{
    public async Task<Result<DeletedHotstringDto[]>> Handle(ListDeletedHotstringsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        // Latest row per deleted entity: a Delete tombstone with no newer history row
        // and no live main-table row (restore brings the item back to life).
        List<EntityHistory> tombstones = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.ChangeType == HistoryChangeType.Delete
                && !db.Hotstrings.Any(x => x.Id == h.EntityId)
                && !db.EntityHistories.Any(newer => newer.EntityType == h.EntityType
                    && newer.EntityId == h.EntityId
                    && newer.Version > h.Version))
            .OrderByDescending(h => h.CapturedAt)
            .ToListAsync(ct);

        DeletedHotstringDto[] items =
        [
            .. tombstones
                .Select(t => (Row: t, Snapshot: JsonSerializer.Deserialize<HotstringSnapshot>(t.SnapshotJson)))
                .Where(x => x.Snapshot is not null)
                .Select(x => new DeletedHotstringDto(
                    x.Row.EntityId,
                    x.Snapshot!.Trigger,
                    x.Snapshot.Replacement,
                    x.Snapshot.Description,
                    x.Row.CapturedAt))
        ];

        return Result.Success(items);
    }
}
```

- [ ] **Step 4: Implement — ListDeletedHotkeysQuery.cs**

Identical shape: `TrackedEntityType.Hotkey`, live check against `db.Hotkeys`, deserialize `HotkeySnapshot`, map to `new DeletedHotkeyDto(x.Row.EntityId, x.Snapshot!.Description, x.Snapshot.Key, x.Snapshot.Ctrl, x.Snapshot.Alt, x.Snapshot.Shift, x.Snapshot.Win, x.Row.CapturedAt)`.

- [ ] **Step 5: Run tests, commit**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~ListDeletedQueryTests" -v minimal`
Expected: PASS (3 tests).

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: recycle-bin list queries"
```

---

### Task 9: Restore commands (both entities)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/RestoreHotstringCommand.cs`
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RestoreHotkeyCommand.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/RestoreCommandTests.cs`

**Interfaces:**
- Consumes: `Hotstring.Restore`/`Hotkey.Restore` (Task 1), tombstones (Task 5), snapshots.
- Produces: `RestoreHotstringCommand(Guid Id)` → `Result<HotstringDto>`; `RestoreHotkeyCommand(Guid Id)` → `Result<HotkeyDto>`. Semantics: latest `Delete` tombstone; re-create with **original Id + CreatedAt**; missing Profile/Category links dropped silently; live row already exists → `Conflict`; no tombstone → `NotFound`; unique-index collision (trigger) → `Conflict`. Restore writes **no** history row (current state = the item, same as Create).

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Application.Tests/History/RestoreCommandTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class RestoreCommandTests(HistoryDbFixture fx)
{
    private async Task DeleteViaHandlerAsync(Guid owner, Guid id)
    {
        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        (await handler.Handle(new DeleteHotstringCommand(id), default)).IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Restore_ReinsertsWithOriginalIdCreatedAtAndLinks()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("rs1")
            .WithProfiles(profile.Id).WithCategory(category.Id).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Categories.Add(category);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteViaHandlerAsync(owner, entity.Id);

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System);

        Result<HotstringDto> result = await handler.Handle(new RestoreHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.CreatedAt.Should().Be(entity.CreatedAt);
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);

        (await db.Hotstrings.AnyAsync(h => h.Id == entity.Id)).Should().BeTrue();
    }

    [Fact]
    public async Task Restore_TriggerNowTaken_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rs2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteViaHandlerAsync(owner, entity.Id);

        // Same trigger re-created with a NEW id.
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder().WithOwner(owner).WithTrigger("rs2").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner), TimeProvider.System);

        Result<HotstringDto> result = await handler.Handle(new RestoreHotstringCommand(entity.Id), default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Restore_NoTombstone_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System);

        Result<HotstringDto> result = await handler.Handle(new RestoreHotstringCommand(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Restore_SnapshotProfileDeleted_RestoresWithZeroLinks()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("rs3").WithProfiles(profile.Id).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteViaHandlerAsync(owner, entity.Id);

        await using (AppDbContext del = fx.CreateContext())
        {
            del.Profiles.Remove(await del.Profiles.SingleAsync(p => p.Id == profile.Id));
            await del.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner), TimeProvider.System);

        Result<HotstringDto> result = await handler.Handle(new RestoreHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~RestoreCommandTests" -v minimal`
Expected: compile error.

- [ ] **Step 3: Implement — RestoreHotstringCommand.cs**

```csharp
using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record RestoreHotstringCommand(Guid Id) : IRequest<Result<HotstringDto>>;

internal sealed class RestoreHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<RestoreHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(RestoreHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool liveExists = await db.Hotstrings
            .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
        if (liveExists)
            return Result.Conflict("The hotstring already exists — nothing to restore.");

        EntityHistory? tombstone = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id
                && h.ChangeType == HistoryChangeType.Delete)
            .OrderByDescending(h => h.Version)
            .FirstOrDefaultAsync(ct);

        if (tombstone is null)
            return Result.NotFound();

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(tombstone.SnapshotJson);
        if (snapshot is null)
            return Result.Error("Snapshot could not be read.");

        Guid[] liveProfileIds = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid && snapshot.ProfileIds.Contains(p.Id))
            .Select(p => p.Id)
            .ToArrayAsync(ct);
        Guid[] liveCategoryIds = await db.Categories
            .Where(c => c.OwnerOid == ownerOid && snapshot.CategoryIds.Contains(c.Id))
            .Select(c => c.Id)
            .ToArrayAsync(ct);

        Hotstring entity = Hotstring.Restore(
            request.Id,
            ownerOid,
            snapshot.Trigger,
            snapshot.Replacement,
            snapshot.Description,
            snapshot.AppliesToAllProfiles,
            snapshot.IsEndingCharacterRequired,
            snapshot.IsTriggerInsideWord,
            snapshot.CreatedAt,
            clock);

        db.Hotstrings.Add(entity);

        if (!snapshot.AppliesToAllProfiles)
        {
            foreach (Guid pid in liveProfileIds)
            {
                var junction = HotstringProfile.Create(entity.Id, pid);
                db.HotstringProfiles.Add(junction);
                entity.Profiles.Add(junction);
            }
        }

        foreach (Guid cid in liveCategoryIds)
        {
            var junction = HotstringCategory.Create(entity.Id, cid);
            db.HotstringCategories.Add(junction);
            entity.Categories.Add(junction);
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return Result.Conflict("A hotstring with this trigger already exists.");
        }

        return Result.Success(entity.ToDto());
    }
}
```

- [ ] **Step 4: Implement — RestoreHotkeyCommand.cs**

Same structure with hotkey types: live check on `db.Hotkeys` (conflict message `"The hotkey already exists — nothing to restore."`), `TrackedEntityType.Hotkey`, `HotkeySnapshot`, `Hotkey.Restore(request.Id, ownerOid, snapshot.Description, snapshot.Key, snapshot.Ctrl, snapshot.Alt, snapshot.Shift, snapshot.Win, snapshot.Action, snapshot.Parameters, snapshot.AppliesToAllProfiles, snapshot.CreatedAt, clock)`, junctions via `HotkeyProfile`/`HotkeyCategory`, duplicate-key message `"A hotkey with this key + modifier combination already exists."`.

- [ ] **Step 5: Run tests, commit**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~RestoreCommandTests" -v minimal`
Expected: PASS (4 tests).

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: restore deleted hotstring/hotkey from tombstone"
```

---

### Task 10: Purge commands — "Delete forever" (both entities)

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/PurgeDeletedHotstringCommand.cs`
- Create: `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/PurgeDeletedHotkeyCommand.cs`
- Test: `tests/AHKFlowApp.Application.Tests/History/PurgeCommandTests.cs`

**Interfaces:**
- Consumes: tombstones (Task 5).
- Produces: `PurgeDeletedHotstringCommand(Guid Id)` → `Result`; `PurgeDeletedHotkeyCommand(Guid Id)` → `Result`. Semantics: only valid from the deleted state — `NotFound` when a live row exists or no `Delete` tombstone exists; on success removes **all** history rows for `(type, id)`.

- [ ] **Step 1: Write the failing tests**

`tests/AHKFlowApp.Application.Tests/History/PurgeCommandTests.cs`:

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class PurgeCommandTests(HistoryDbFixture fx)
{
    private async Task<Hotstring> SeedEditAndDeleteAsync(Guid owner, string trigger)
    {
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger(trigger).Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
            await recorder.RecordHotstringAsync(entity, Domain.Enums.HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        (await handler.Handle(new DeleteHotstringCommand(entity.Id), default)).IsSuccess.Should().BeTrue();
        return entity;
    }

    [Fact]
    public async Task Purge_RemovesAllHistoryRows()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = await SeedEditAndDeleteAsync(owner, "pg1");

        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new PurgeDeletedHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        (await db.EntityHistories.AnyAsync(h => h.EntityId == entity.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task Purge_LiveItem_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        Hotstring live = new HotstringBuilder().WithOwner(owner).WithTrigger("pg2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(live);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new PurgeDeletedHotstringCommand(live.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Purge_UnknownId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotstringCommandHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result result = await handler.Handle(new PurgeDeletedHotstringCommand(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~PurgeCommandTests" -v minimal`
Expected: compile error.

- [ ] **Step 3: Implement — PurgeDeletedHotstringCommand.cs**

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record PurgeDeletedHotstringCommand(Guid Id) : IRequest<Result>;

internal sealed class PurgeDeletedHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<PurgeDeletedHotstringCommand, Result>
{
    public async Task<Result> Handle(PurgeDeletedHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool liveExists = await db.Hotstrings
            .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
        if (liveExists)
            return Result.NotFound();

        List<EntityHistory> rows = await db.EntityHistories
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id)
            .ToListAsync(ct);

        if (!rows.Any(r => r.ChangeType == HistoryChangeType.Delete))
            return Result.NotFound();

        db.EntityHistories.RemoveRange(rows);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
```

- [ ] **Step 4: Implement — PurgeDeletedHotkeyCommand.cs**

Identical with `TrackedEntityType.Hotkey` and the live check against `db.Hotkeys`.

- [ ] **Step 5: Run tests, commit**

Run: `dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~PurgeCommandTests" -v minimal`
Expected: PASS (3 tests).

```bash
git add src/Backend/AHKFlowApp.Application tests/AHKFlowApp.Application.Tests
git commit -m "feat: purge (delete forever) commands"
```

---

### Task 11: API endpoints (both controllers) + endpoint tests

**Files:**
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotstringsController.cs`
- Modify: `src/Backend/AHKFlowApp.API/Controllers/HotkeysController.cs`
- Test: `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringHistoryEndpointsTests.cs`
- Test: `tests/AHKFlowApp.API.Tests/Hotkeys/HotkeyHistoryEndpointsTests.cs`

**Interfaces:**
- Consumes: all commands/queries from Tasks 6–10.
- Produces (mirrored by the frontend clients in Task 12):

```
GET    api/v1/hotstrings/{id}/history                  -> HistoryEntryDto[]        200/404
GET    api/v1/hotstrings/{id}/history/{version}        -> HotstringHistoryVersionDto 200/404
POST   api/v1/hotstrings/{id}/history/{version}/revert -> HotstringDto             200/404/409
GET    api/v1/hotstrings/deleted                       -> DeletedHotstringDto[]    200
POST   api/v1/hotstrings/{id}/restore                  -> HotstringDto             200/404/409
DELETE api/v1/hotstrings/deleted/{id}                  -> (purge)                  204/404
```

Same six on `api/v1/hotkeys` with hotkey DTOs. (`deleted` is not a guid, so it can't collide with `{id:guid}` routes.)

- [ ] **Step 1: Write the failing API tests**

`tests/AHKFlowApp.API.Tests/Hotstrings/HotstringHistoryEndpointsTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringHistoryEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    private static async Task<HotstringDto> CreateAsync(HttpClient client, string trigger)
    {
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/hotstrings", new CreateHotstringDto(trigger, "original"));
        created.EnsureSuccessStatusCode();
        return (await created.Content.ReadFromJsonAsync<HotstringDto>())!;
    }

    [Fact]
    public async Task History_AfterEdit_ListsVersionAndVersionDetailReturnsSnapshot()
    {
        using HttpClient client = CreateAuthed();
        HotstringDto dto = await CreateAsync(client, "he1");
        HttpResponseMessage put = await client.PutAsJsonAsync($"/api/v1/hotstrings/{dto.Id}",
            new UpdateHotstringDto("he1", "changed", null, true, true, true, null));
        put.EnsureSuccessStatusCode();

        HistoryEntryDto[]? entries = await client.GetFromJsonAsync<HistoryEntryDto[]>(
            $"/api/v1/hotstrings/{dto.Id}/history");
        entries.Should().ContainSingle();
        entries![0].Version.Should().Be(1);

        HotstringHistoryVersionDto? version = await client.GetFromJsonAsync<HotstringHistoryVersionDto>(
            $"/api/v1/hotstrings/{dto.Id}/history/1");
        version!.Snapshot.Replacement.Should().Be("original");
    }

    [Fact]
    public async Task History_OtherUsersItem_Returns404()
    {
        using HttpClient a = CreateAuthed();
        HotstringDto dto = await CreateAsync(a, "he2");

        using HttpClient b = CreateAuthed();
        HttpResponseMessage response = await b.GetAsync($"/api/v1/hotstrings/{dto.Id}/history");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Revert_RestoresPreviousStateAndReturnsUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HotstringDto dto = await CreateAsync(client, "he3");
        HttpResponseMessage put = await client.PutAsJsonAsync($"/api/v1/hotstrings/{dto.Id}",
            new UpdateHotstringDto("he3", "changed", null, true, true, true, null));
        put.EnsureSuccessStatusCode();

        HttpResponseMessage revert = await client.PostAsync(
            $"/api/v1/hotstrings/{dto.Id}/history/1/revert", content: null);

        revert.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? reverted = await revert.Content.ReadFromJsonAsync<HotstringDto>();
        reverted!.Replacement.Should().Be("original");
    }

    [Fact]
    public async Task DeleteRestorePurge_RoundTripsThroughRecycleBin()
    {
        using HttpClient client = CreateAuthed();
        HotstringDto dto = await CreateAsync(client, "he4");

        (await client.DeleteAsync($"/api/v1/hotstrings/{dto.Id}")).EnsureSuccessStatusCode();

        DeletedHotstringDto[]? deleted = await client.GetFromJsonAsync<DeletedHotstringDto[]>(
            "/api/v1/hotstrings/deleted");
        deleted.Should().Contain(d => d.Id == dto.Id);

        HttpResponseMessage restore = await client.PostAsync($"/api/v1/hotstrings/{dto.Id}/restore", content: null);
        restore.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? restored = await restore.Content.ReadFromJsonAsync<HotstringDto>();
        restored!.Id.Should().Be(dto.Id);
        restored.Trigger.Should().Be("he4");

        // Delete again, then purge forever.
        (await client.DeleteAsync($"/api/v1/hotstrings/{dto.Id}")).EnsureSuccessStatusCode();
        HttpResponseMessage purge = await client.DeleteAsync($"/api/v1/hotstrings/deleted/{dto.Id}");
        purge.StatusCode.Should().Be(HttpStatusCode.NoContent);

        DeletedHotstringDto[]? after = await client.GetFromJsonAsync<DeletedHotstringDto[]>(
            "/api/v1/hotstrings/deleted");
        after.Should().NotContain(d => d.Id == dto.Id);
        HttpResponseMessage history = await client.GetAsync($"/api/v1/hotstrings/{dto.Id}/history");
        history.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Endpoints_WithoutAuth_Return401()
    {
        using HttpClient anon = _factory.CreateClient();

        (await anon.GetAsync($"/api/v1/hotstrings/{Guid.NewGuid()}/history"))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await anon.GetAsync("/api/v1/hotstrings/deleted"))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

`tests/AHKFlowApp.API.Tests/Hotkeys/HotkeyHistoryEndpointsTests.cs` — same five tests against `/api/v1/hotkeys` with `CreateHotkeyDto`/`UpdateHotkeyDto`/`HotkeyHistoryVersionDto`/`DeletedHotkeyDto` (create with `new CreateHotkeyDto("desc", "F5")`, update the description, assert `Snapshot.Description`). Mirror the structure exactly; check `HotkeysEndpointsTests.cs` for existing create/update payload examples.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotstringHistoryEndpointsTests|FullyQualifiedName~HotkeyHistoryEndpointsTests" -v minimal`
Expected: FAIL — 404 on unknown routes (compile passes; DTOs exist).

- [ ] **Step 3: Implement — HotstringsController actions**

Append after the existing `Delete` action (add usings `AHKFlowApp.Application.Queries.Hotstrings` is already present; commands namespace too):

```csharp
    /// <summary>List saved versions of a hotstring, newest first.</summary>
    [HttpGet("{id:guid}/history")]
    [ProducesResponseType(typeof(HistoryEntryDto[]), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HistoryEntryDto[]>> GetHistory(Guid id, CancellationToken ct) =>
        (await mediator.Send(new GetHotstringHistoryQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Get one saved version of a hotstring, including its snapshot.</summary>
    [HttpGet("{id:guid}/history/{version:int}")]
    [ProducesResponseType(typeof(HotstringHistoryVersionDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HotstringHistoryVersionDto>> GetHistoryVersion(Guid id, int version, CancellationToken ct) =>
        (await mediator.Send(new GetHotstringHistoryVersionQuery(id, version), ct)).ToProblemActionResult(this);

    /// <summary>Revert a hotstring to a saved version. Returns the updated representation.</summary>
    [HttpPost("{id:guid}/history/{version:int}/revert")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Revert(Guid id, int version, CancellationToken ct) =>
        (await mediator.Send(new RevertHotstringCommand(id, version), ct)).ToProblemActionResult(this);

    /// <summary>List deleted hotstrings that can be restored (Recycle Bin).</summary>
    [HttpGet("deleted")]
    [ProducesResponseType(typeof(DeletedHotstringDto[]), StatusCodes.Status200OK)]
    public async Task<ActionResult<DeletedHotstringDto[]>> ListDeleted(CancellationToken ct) =>
        (await mediator.Send(new ListDeletedHotstringsQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Restore a deleted hotstring with its original id and links.</summary>
    [HttpPost("{id:guid}/restore")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Restore(Guid id, CancellationToken ct) =>
        (await mediator.Send(new RestoreHotstringCommand(id), ct)).ToProblemActionResult(this);

    /// <summary>Permanently remove a deleted hotstring's history ("Delete forever").</summary>
    [HttpDelete("deleted/{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Purge(Guid id, CancellationToken ct)
    {
        Result result = await mediator.Send(new PurgeDeletedHotstringCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
```

- [ ] **Step 4: Implement — HotkeysController actions**

Same six actions with hotkey commands/queries and DTOs (`GetHotkeyHistoryQuery`, `GetHotkeyHistoryVersionQuery`, `RevertHotkeyCommand`, `ListDeletedHotkeysQuery`, `RestoreHotkeyCommand`, `PurgeDeletedHotkeyCommand`; `HotkeyHistoryVersionDto`, `DeletedHotkeyDto`, `HotkeyDto`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotstringHistoryEndpointsTests|FullyQualifiedName~HotkeyHistoryEndpointsTests|FullyQualifiedName~ProducesResponseTypeCoverageTests|FullyQualifiedName~SwaggerDocTests" -v minimal`
Expected: PASS (history endpoints + OpenAPI coverage gates).

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.API tests/AHKFlowApp.API.Tests
git commit -m "feat: history/revert/restore/purge endpoints"
```

---

### Task 12: Frontend — DTOs + API-client methods

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HistoryDtos.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotstringsApiClient.cs` + `HotstringsApiClient.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Services/IHotkeysApiClient.cs` + `HotkeysApiClient.cs`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs` (add tests)
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotkeysApiClientTests.cs` (add tests)

**Interfaces:**
- Consumes: Task 11 routes; `ApiClientBase.SendAsync<T>` / `SendNoContentAsync`.
- Produces (used by Tasks 13–14):

```csharp
// on IHotstringsApiClient (and IHotkeysApiClient with hotkey DTOs)
Task<ApiResult<HistoryEntryDto[]>> GetHistoryAsync(Guid id, CancellationToken ct = default);
Task<ApiResult<HotstringHistoryVersionDto>> GetHistoryVersionAsync(Guid id, int version, CancellationToken ct = default);
Task<ApiResult<HotstringDto>> RevertAsync(Guid id, int version, CancellationToken ct = default);
Task<ApiResult<DeletedHotstringDto[]>> ListDeletedAsync(CancellationToken ct = default);
Task<ApiResult<HotstringDto>> RestoreAsync(Guid id, CancellationToken ct = default);
Task<ApiResult> PurgeDeletedAsync(Guid id, CancellationToken ct = default);
```

- [ ] **Step 1: Create the frontend DTOs**

`src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HistoryDtos.cs` (frontend keeps its own DTO copies, like `HotkeyAction`; enum values must match the backend numerically):

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public enum HistoryChangeType
{
    Edit = 1,
    Delete = 2,
}

public sealed record HistoryEntryDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt);

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
    DateTimeOffset UpdatedAt);

public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record HotstringHistoryVersionDto(
    int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt, HotstringSnapshot Snapshot);

public sealed record HotkeyHistoryVersionDto(
    int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt, HotkeySnapshot Snapshot);

public sealed record DeletedHotstringDto(
    Guid Id, string Trigger, string Replacement, string? Description, DateTimeOffset DeletedAt);

public sealed record DeletedHotkeyDto(
    Guid Id, string Description, string Key, bool Ctrl, bool Alt, bool Shift, bool Win, DateTimeOffset DeletedAt);
```

- [ ] **Step 2: Write the failing client tests**

Append to `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs`:

```csharp
    [Fact]
    public async Task GetHistoryAsync_OnSuccess_ReturnsEntries()
    {
        HistoryEntryDto[] entries = [new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)];
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, entries);
        var id = Guid.NewGuid();

        ApiResult<HistoryEntryDto[]> result = await ClientWith(handler).GetHistoryAsync(id);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotstrings/{id}/history");
    }

    [Fact]
    public async Task RevertAsync_PostsToRevertRoute()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, []);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotstringDto> result = await ClientWith(handler).RevertAsync(dto.Id, 2);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotstrings/{dto.Id}/history/2/revert");
    }

    [Fact]
    public async Task ListDeletedAsync_GetsDeletedRoute()
    {
        DeletedHotstringDto[] deleted = [new(Guid.NewGuid(), "btw", "by the way", null, DateTimeOffset.UtcNow)];
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, deleted);

        ApiResult<DeletedHotstringDto[]> result = await ClientWith(handler).ListDeletedAsync();

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be("/api/v1/hotstrings/deleted");
    }

    [Fact]
    public async Task PurgeDeletedAsync_SendsDeleteToDeletedRoute()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);
        var id = Guid.NewGuid();

        ApiResult result = await ClientWith(handler).PurgeDeletedAsync(id);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Delete);
        handler.LastRequest.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotstrings/deleted/{id}");
    }
```

Check `StubHttpMessageHandler` for the no-content factory's real name (`StatusResponse` may differ) and adjust. Add the equivalent four tests to `HotkeysApiClientTests.cs` (paths under `/api/v1/hotkeys`, hotkey DTO constructors).

- [ ] **Step 3: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsApiClientTests|FullyQualifiedName~HotkeysApiClientTests" -v minimal`
Expected: compile error — methods missing.

- [ ] **Step 4: Implement the client methods**

Add to `IHotstringsApiClient.cs` the six signatures from the Interfaces block. Add to `HotstringsApiClient.cs`:

```csharp
    public Task<ApiResult<HistoryEntryDto[]>> GetHistoryAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HistoryEntryDto[]>(HttpMethod.Get, $"{BasePath}/{id}/history", content: null, ct);

    public Task<ApiResult<HotstringHistoryVersionDto>> GetHistoryVersionAsync(Guid id, int version, CancellationToken ct = default) =>
        SendAsync<HotstringHistoryVersionDto>(HttpMethod.Get, $"{BasePath}/{id}/history/{version}", content: null, ct);

    public Task<ApiResult<HotstringDto>> RevertAsync(Guid id, int version, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, $"{BasePath}/{id}/history/{version}/revert", content: null, ct);

    public Task<ApiResult<DeletedHotstringDto[]>> ListDeletedAsync(CancellationToken ct = default) =>
        SendAsync<DeletedHotstringDto[]>(HttpMethod.Get, $"{BasePath}/deleted", content: null, ct);

    public Task<ApiResult<HotstringDto>> RestoreAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, $"{BasePath}/{id}/restore", content: null, ct);

    public Task<ApiResult> PurgeDeletedAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/deleted/{id}", ct);
```

Mirror on `IHotkeysApiClient.cs` / `HotkeysApiClient.cs` with `HotkeyHistoryVersionDto`, `DeletedHotkeyDto`, `HotkeyDto`.

- [ ] **Step 5: Run tests, commit**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HotstringsApiClientTests|FullyQualifiedName~HotkeysApiClientTests" -v minimal`
Expected: PASS.

```bash
git add src/Frontend tests/AHKFlowApp.UI.Blazor.Tests
git commit -m "feat: history/restore/purge api-client methods"
```

---

### Task 13: History dialogs + page wiring (both entity pages)

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotstrings/HotstringHistoryDialog.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Components/Hotkeys/HotkeyHistoryDialog.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` (History row action + handler)
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` (History row action + handler)
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringHistoryDialogTests.cs`
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotkeys/HotkeyHistoryDialogTests.cs`

**Interfaces:**
- Consumes: Task 12 client methods (`GetHistoryAsync`, `GetHistoryVersionAsync`, `RevertAsync`).
- Produces: `HotstringHistoryDialog` with parameters `Guid HotstringId`, `string Trigger`; closes with `DialogResult.Ok(true)` after a successful revert (pages reload the grid on that result). `HotkeyHistoryDialog` twin with `Guid HotkeyId`, `string Description`.

Before writing markup, verify `MudDialog`, `MudList`/`MudListItem` (T-typed, `SelectedValue`), and `IMudDialogInstance` parameters via `mcp__mudblazor__get_component_parameters`. Follow the established dialog pattern in `Components/Hotstrings/HotstringEditDialog.razor`.

- [ ] **Step 1: Write the failing bUnit tests**

`tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringHistoryDialogTests.cs` (follow the dialog-test setup used in `HotstringEditDialogTests.cs` — render `MudPopoverProvider` + `MudDialogProvider`, open via `IDialogService`):

```csharp
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringHistoryDialogTests : BunitContext
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();
    private readonly Guid _id = Guid.NewGuid();

    public HotstringHistoryDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private async Task<IRenderedComponent<MudDialogProvider>> OpenDialogAsync()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        var dialogService = Services.GetRequiredService<IDialogService>();
        var parameters = new DialogParameters<HotstringHistoryDialog>
        {
            { x => x.HotstringId, _id },
            { x => x.Trigger, "btw" },
        };
        await provider.InvokeAsync(() => dialogService.ShowAsync<HotstringHistoryDialog>("History", parameters));
        return provider;
    }

    [Fact]
    public async Task Dialog_RendersVersionsFromApi()
    {
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok(
                [new(2, HistoryChangeType.Edit, DateTimeOffset.UtcNow), new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v2"));
        provider.Markup.Should().Contain("v1");
    }

    [Fact]
    public async Task Dialog_NoHistory_ShowsEmptyMessage()
    {
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([]));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("No history yet"));
    }

    [Fact]
    public async Task Dialog_SelectVersionAndRevert_CallsRevertApi()
    {
        var snapshot = new HotstringSnapshot("btw", "old text", null, true, true, true, [], [],
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));
        _api.GetHistoryVersionAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringHistoryVersionDto>.Ok(
                new HotstringHistoryVersionDto(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow, snapshot)));
        _api.RevertAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(_id, [], true, "btw", "old text", null, true, true,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, [])));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        provider.Find(".history-version").Click();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("old text"));

        provider.Find(".revert-version").Click();
        provider.WaitForAssertion(() =>
            _api.Received(1).RevertAsync(_id, 1, Arg.Any<CancellationToken>()));
    }
}
```

`HotkeyHistoryDialogTests.cs` — same three tests with hotkey types (`HotkeyId`, `Description` parameters; `HotkeySnapshot`; assert the preview shows the snapshot `Key`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HistoryDialogTests" -v minimal`
Expected: compile error — dialogs don't exist.

- [ ] **Step 3: Implement — HotstringHistoryDialog.razor**

```razor
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using MudBlazor

<MudDialog>
    <DialogContent>
        @if (_loading)
        {
            <MudProgressCircular Indeterminate="true" />
        }
        else if (_error is not null)
        {
            <MudAlert Severity="Severity.Error">@_error</MudAlert>
        }
        else if (_entries.Length == 0)
        {
            <MudText>No history yet — versions appear after the first edit.</MudText>
        }
        else
        {
            <MudStack Row="true" Spacing="4">
                <MudList T="HistoryEntryDto" Dense="true">
                    @foreach (HistoryEntryDto entry in _entries)
                    {
                        <MudListItem T="HistoryEntryDto" Class="history-version"
                                     OnClick="() => SelectAsync(entry)">
                            <MudStack Row="true" Spacing="2" AlignItems="AlignItems.Center">
                                <MudChip T="string" Size="Size.Small"
                                         Color="@(entry.ChangeType == HistoryChangeType.Delete ? Color.Error : Color.Default)">
                                    v@(entry.Version)
                                </MudChip>
                                <MudText Typo="Typo.body2">@entry.ChangeType</MudText>
                                <MudText Typo="Typo.caption">@entry.CapturedAt.ToLocalTime().ToString("g")</MudText>
                            </MudStack>
                        </MudListItem>
                    }
                </MudList>
                @if (_preview is not null)
                {
                    <MudPaper Class="pa-3" Style="min-width: 280px;">
                        <MudText Typo="Typo.subtitle2">Trigger</MudText>
                        <MudText Class="mb-2">@_preview.Snapshot.Trigger</MudText>
                        <MudText Typo="Typo.subtitle2">Replacement</MudText>
                        <MudText Class="mb-2">@_preview.Snapshot.Replacement</MudText>
                        @if (_preview.Snapshot.Description is { Length: > 0 } description)
                        {
                            <MudText Typo="Typo.subtitle2">Description</MudText>
                            <MudText Class="mb-2">@description</MudText>
                        }
                        <MudText Typo="Typo.caption">
                            @(_preview.Snapshot.AppliesToAllProfiles
                                ? "All profiles"
                                : $"{_preview.Snapshot.ProfileIds.Length} profile(s)") ·
                            @(_preview.Snapshot.CategoryIds.Length) categorie(s)
                        </MudText>
                    </MudPaper>
                }
            </MudStack>
        }
    </DialogContent>
    <DialogActions>
        <MudButton OnClick="Close">Close</MudButton>
        <MudButton Class="revert-version" Color="Color.Primary" Variant="Variant.Filled"
                   Disabled="@(_preview is null || _busy)" OnClick="RevertAsync">
            Revert to this version
        </MudButton>
    </DialogActions>
</MudDialog>

@code {
    [CascadingParameter] private IMudDialogInstance MudDialog { get; set; } = default!;
    [Inject] private IHotstringsApiClient Api { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;

    [Parameter] public Guid HotstringId { get; set; }
    [Parameter] public string Trigger { get; set; } = string.Empty;

    private HistoryEntryDto[] _entries = [];
    private HotstringHistoryVersionDto? _preview;
    private bool _loading = true;
    private bool _busy;
    private string? _error;

    protected override async Task OnInitializedAsync()
    {
        ApiResult<HistoryEntryDto[]> result = await Api.GetHistoryAsync(HotstringId);
        if (result.IsSuccess)
            _entries = result.Value!;
        else
            _error = ApiErrorMessageFactory.Build(result.Status, result.Problem);
        _loading = false;
    }

    private async Task SelectAsync(HistoryEntryDto entry)
    {
        ApiResult<HotstringHistoryVersionDto> result = await Api.GetHistoryVersionAsync(HotstringId, entry.Version);
        if (result.IsSuccess)
            _preview = result.Value;
        else
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }

    private async Task RevertAsync()
    {
        if (_preview is null)
            return;

        bool? confirm = await DialogService.ShowMessageBoxAsync(
            title: "Revert hotstring?",
            message: $"Revert \"{Trigger}\" to version {_preview.Version}? The current state is saved to history first.",
            yesText: "Revert", cancelText: "Cancel");
        if (confirm != true)
            return;

        _busy = true;
        ApiResult<HotstringDto> result = await Api.RevertAsync(HotstringId, _preview.Version);
        _busy = false;
        if (result.IsSuccess)
        {
            Snackbar.Add($"Reverted to version {_preview.Version}.", Severity.Success);
            MudDialog.Close(DialogResult.Ok(true));
        }
        else
        {
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }

    private void Close() => MudDialog.Cancel();
}
```

Match `ShowMessageBoxAsync` and `IMudDialogInstance` names to what the existing pages/dialogs actually use (the pages call `DialogService.ShowMessageBoxAsync`; `HotstringEditDialog.razor` shows the current dialog-instance cascading parameter type).

- [ ] **Step 4: Implement — HotkeyHistoryDialog.razor**

Same structure: parameters `Guid HotkeyId`, `string Description`; inject `IHotkeysApiClient`; preview shows `Description`, key combo (`Ctrl`/`Alt`/`Shift`/`Win` + `Key`), `Action`, `Parameters`; revert confirm text `$"Revert \"{Description}\" to version {_preview.Version}? …"`.

- [ ] **Step 5: Wire the History action into both pages**

`Pages/Hotstrings.razor` — in `RenderActions`, add before the delete button (else-branch):

```razor
            <MudIconButton Class="show-history" Icon="@Icons.Material.Filled.History"
                           OnClick="() => ShowHistoryAsync(item)" />
```

Add the handler next to `DeleteAsync` (add `@using AHKFlowApp.UI.Blazor.Components.Hotstrings` if not present):

```csharp
    private async Task ShowHistoryAsync(HotstringEditModel item)
    {
        if (item.Id is not { } id)
            return;

        var parameters = new DialogParameters<HotstringHistoryDialog>
        {
            { x => x.HotstringId, id },
            { x => x.Trigger, item.Trigger },
        };
        IDialogReference dialog = await DialogService.ShowAsync<HotstringHistoryDialog>(
            $"History — {item.Trigger}", parameters);
        DialogResult? result = await dialog.Result;
        if (result is { Canceled: false })
        {
            ClearListCache();
            if (_grid is not null)
                await _grid.ReloadServerData();
        }
    }
```

`Pages/Hotkeys.razor` — same: `show-history` icon button in its actions template + `ShowHistoryAsync(HotkeyEditModel item)` opening `HotkeyHistoryDialog` with `HotkeyId`/`Description`, reloading the grid on non-canceled close (mirror that page's existing reload calls).

- [ ] **Step 6: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~HistoryDialogTests|FullyQualifiedName~HotstringsPageTests|FullyQualifiedName~HotkeysPageTests" -v minimal`
Expected: PASS (new dialog tests + untouched page tests still green).

- [ ] **Step 7: Commit**

```bash
git add src/Frontend tests/AHKFlowApp.UI.Blazor.Tests
git commit -m "feat: history dialog + row action on hotstring/hotkey pages"
```

---

### Task 14: Recycle Bin page, nav entry, softened delete copy

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/RecycleBin.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` (3 delete-confirm messages)
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor` (3 delete-confirm messages)
- Test: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/RecycleBinPageTests.cs`

**Interfaces:**
- Consumes: `ListDeletedAsync`, `RestoreAsync`, `PurgeDeletedAsync` on both clients (Task 12).
- Produces: `/recycle-bin` page. **Leave `Profiles.razor` and `Categories.razor` delete copy untouched** — those entities are not versioned in v1.

- [ ] **Step 1: Write the failing page tests**

`tests/AHKFlowApp.UI.Blazor.Tests/Pages/RecycleBinPageTests.cs` (setup mirrors `CategoriesPageTests`, with **both** clients substituted):

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

public sealed class RecycleBinPageTests : BunitContext
{
    private readonly IHotstringsApiClient _hotstringsApi = Substitute.For<IHotstringsApiClient>();
    private readonly IHotkeysApiClient _hotkeysApi = Substitute.For<IHotkeysApiClient>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public RecycleBinPageTests()
    {
        Services.AddSingleton(_hotstringsApi);
        Services.AddSingleton(_hotkeysApi);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<RecycleBin> RenderPage()
    {
        Render<MudPopoverProvider>();
        Render<MudDialogProvider>();
        return Render<RecycleBin>(p => p.AddCascadingValue(AuthenticatedState));
    }

    private void StubDeleted(DeletedHotstringDto[]? hotstrings = null, DeletedHotkeyDto[]? hotkeys = null)
    {
        _hotstringsApi.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotstringDto[]>.Ok(hotstrings ?? []));
        _hotkeysApi.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotkeyDto[]>.Ok(hotkeys ?? []));
    }

    [Fact]
    public void Page_RendersDeletedItemsOfBothTypes()
    {
        StubDeleted(
            [new(Guid.NewGuid(), "btw", "by the way", null, DateTimeOffset.UtcNow)],
            [new(Guid.NewGuid(), "Open terminal", "T", true, false, false, false, DateTimeOffset.UtcNow)]);

        IRenderedComponent<RecycleBin> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("btw");
            cut.Markup.Should().Contain("Open terminal");
        });
    }

    [Fact]
    public void Page_EmptyBin_ShowsEmptyMessage()
    {
        StubDeleted();

        IRenderedComponent<RecycleBin> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Recycle Bin is empty"));
    }

    [Fact]
    public void Restore_CallsRestoreAndReloads()
    {
        var id = Guid.NewGuid();
        StubDeleted([new(id, "btw", "by the way", null, DateTimeOffset.UtcNow)]);
        _hotstringsApi.RestoreAsync(id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(id, [], true, "btw", "by the way", null, true, true,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, [])));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("btw"));

        cut.Find(".restore-item").Click();

        cut.WaitForAssertion(() =>
            _hotstringsApi.Received(1).RestoreAsync(id, Arg.Any<CancellationToken>()));
    }
}
```

(A purge click-through test requires confirming a message box; keep it if straightforward with the message-box test helper used elsewhere, otherwise the purge path is covered by API tests + manual verification.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~RecycleBinPageTests" -v minimal`
Expected: compile error — page doesn't exist.

- [ ] **Step 3: Implement — RecycleBin.razor**

```razor
@page "/recycle-bin"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using MudBlazor
@using Microsoft.AspNetCore.Components.Authorization

<PageTitle>Recycle Bin</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Recycle Bin</MudText>

<MudPaper Class="pa-4">
    @if (_loadError is not null)
    {
        <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
    }

    @if (!_loading && _rows.Count == 0)
    {
        <MudText>The Recycle Bin is empty.</MudText>
    }
    else
    {
        <MudTable T="RecycleBinRow" Items="_rows" Loading="_loading" Dense="true" Hover="true"
                  Class="recycle-bin-table">
            <HeaderContent>
                <MudTh>Type</MudTh>
                <MudTh>Name</MudTh>
                <MudTh>Details</MudTh>
                <MudTh>Deleted</MudTh>
                <MudTh Style="width:220px" />
            </HeaderContent>
            <RowTemplate>
                <MudTd DataLabel="Type">
                    <MudChip T="string" Size="Size.Small">@context.Type</MudChip>
                </MudTd>
                <MudTd DataLabel="Name">@context.Name</MudTd>
                <MudTd DataLabel="Details">@context.Details</MudTd>
                <MudTd DataLabel="Deleted">@context.DeletedAt.ToLocalTime().ToString("g")</MudTd>
                <MudTd>
                    <MudButton Class="restore-item" Size="Size.Small" Variant="Variant.Filled"
                               Color="Color.Primary" StartIcon="@Icons.Material.Filled.RestoreFromTrash"
                               OnClick="() => RestoreAsync(context)">
                        Restore
                    </MudButton>
                    <MudButton Class="purge-item" Size="Size.Small" Variant="Variant.Outlined"
                               Color="Color.Error" StartIcon="@Icons.Material.Filled.DeleteForever"
                               OnClick="() => PurgeAsync(context)">
                        Delete forever
                    </MudButton>
                </MudTd>
            </RowTemplate>
        </MudTable>
    }
</MudPaper>

@code {
    [Inject] private IHotstringsApiClient HotstringsApi { get; set; } = default!;
    [Inject] private IHotkeysApiClient HotkeysApi { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;

    private sealed record RecycleBinRow(Guid Id, string Type, string Name, string Details, DateTimeOffset DeletedAt);

    private List<RecycleBinRow> _rows = [];
    private bool _loading = true;
    private string? _loadError;

    protected override Task OnInitializedAsync() => LoadAsync();

    private async Task LoadAsync()
    {
        _loading = true;
        _loadError = null;

        ApiResult<DeletedHotstringDto[]> hotstrings = await HotstringsApi.ListDeletedAsync();
        ApiResult<DeletedHotkeyDto[]> hotkeys = await HotkeysApi.ListDeletedAsync();

        if (!hotstrings.IsSuccess || !hotkeys.IsSuccess)
        {
            ApiResult failed = hotstrings.IsSuccess ? hotkeys : hotstrings;
            _loadError = ApiErrorMessageFactory.Build(failed.Status, failed.Problem);
            _loading = false;
            return;
        }

        _rows =
        [
            .. hotstrings.Value!.Select(h => new RecycleBinRow(
                h.Id, "Hotstring", h.Trigger, h.Replacement, h.DeletedAt)),
            .. hotkeys.Value!.Select(h => new RecycleBinRow(
                h.Id, "Hotkey", h.Description, FormatCombo(h), h.DeletedAt)),
        ];
        _rows = [.. _rows.OrderByDescending(r => r.DeletedAt)];
        _loading = false;
    }

    private static string FormatCombo(DeletedHotkeyDto h)
    {
        List<string> parts = [];
        if (h.Ctrl) parts.Add("Ctrl");
        if (h.Alt) parts.Add("Alt");
        if (h.Shift) parts.Add("Shift");
        if (h.Win) parts.Add("Win");
        parts.Add(h.Key);
        return string.Join("+", parts);
    }

    private async Task RestoreAsync(RecycleBinRow row)
    {
        ApiResult result = row.Type == "Hotstring"
            ? await HotstringsApi.RestoreAsync(row.Id)
            : await HotkeysApi.RestoreAsync(row.Id);

        if (result.IsSuccess)
        {
            Snackbar.Add($"{row.Type} \"{row.Name}\" restored.", Severity.Success);
            await LoadAsync();
        }
        else
        {
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }

    private async Task PurgeAsync(RecycleBinRow row)
    {
        bool? confirm = await DialogService.ShowMessageBoxAsync(
            title: "Delete forever?",
            message: $"Permanently delete \"{row.Name}\" and all of its history? This cannot be undone.",
            yesText: "Delete forever", cancelText: "Cancel");
        if (confirm != true)
            return;

        ApiResult result = row.Type == "Hotstring"
            ? await HotstringsApi.PurgeDeletedAsync(row.Id)
            : await HotkeysApi.PurgeDeletedAsync(row.Id);

        if (result.IsSuccess)
        {
            Snackbar.Add($"{row.Type} \"{row.Name}\" permanently deleted.", Severity.Success);
            await LoadAsync();
        }
        else
        {
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }
}
```

Note: `ApiResult<T>` must be assignable to a common shape for the ternaries — if `ApiResult<T>` doesn't derive from `ApiResult`, split the branches into `if/else` storing `IsSuccess`/`Status`/`Problem` instead (check `Services/ApiResult.cs` first).

- [ ] **Step 4: Nav entry + delete copy**

`Layout/NavMenu.razor` — after the Categories link:

```razor
    <MudNavLink Href="recycle-bin"
                Icon="@Icons.Material.Filled.RestoreFromTrash">
        Recycle Bin
    </MudNavLink>
```

Delete-copy changes (6 spots — hotstring/hotkey pages only):
- `Hotstrings.razor:507` → `message: $"Delete \"{item.Trigger}\"? You can restore it from the Recycle Bin.",`
- `Hotstrings.razor:535` and the mobile variant (~line 664) → `message: $"Delete {ids.Length} hotstring(s)? You can restore them from the Recycle Bin.",` (mobile uses `ids.Count`)
- `Hotkeys.razor:570` → `message: $"Delete \"{item.Description}\"? You can restore it from the Recycle Bin.",`
- `Hotkeys.razor:598` and ~line 727 → `message: $"Delete {ids.Length} hotkey(s)? You can restore them from the Recycle Bin.",` (mobile uses `ids.Count`)

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~RecycleBinPageTests|FullyQualifiedName~HotstringsPageTests|FullyQualifiedName~HotkeysPageTests" -v minimal`
Expected: PASS. If existing page tests assert the old "This cannot be undone." copy, update those assertions here.

- [ ] **Step 6: Commit**

```bash
git add src/Frontend tests/AHKFlowApp.UI.Blazor.Tests
git commit -m "feat: recycle bin page + nav + softened delete copy"
```

---

### Task 15: Full verification (automated + manual E2E)

**Files:** none (verification only; fix-ups as needed).

- [ ] **Step 1: Full build + test + format**

```bash
dotnet build --configuration Release
dotnet test --configuration Release --no-build --verbosity normal
dotnet format --verify-no-changes
```

Expected: build succeeds, all tests pass, no formatting drift. Fix anything that fails before proceeding.

- [ ] **Step 2: Manual E2E (spec "Verification" section)**

Start the stack (API with Docker SQL profile + Blazor; see AGENTS.md commands), then use the `playwright-cli` skill for browser verification:

1. Create a hotstring, edit it twice, open **History** → two versions listed; revert to v1 → fields + profile/category links match the original.
2. Delete a hotstring → appears in **Recycle Bin** → **Restore** → reappears in the list with the same content; delete dialog now says "You can restore it from the Recycle Bin."
3. Repeat for a hotkey (modifiers + action preserved through revert/restore).
4. Restore into a colliding trigger → clear conflict message.
5. Delete a hotstring, **Delete forever** in Recycle Bin → gone from the bin; `GET /api/v1/hotstrings/{id}/history` → 404.

- [ ] **Step 3: Commit any fix-ups, then finish the branch**

Use superpowers:finishing-a-development-branch — run the final gate, then create the PR per the repo's GitHub Flow.

---

## Deviations & Notes

- **No FluentValidation validators** for the new commands: all inputs are route-bound (`Guid`, `int`); invalid values naturally yield `NotFound`. Adding validators would be ceremony (YAGNI).
- **Restore writes no history row** — mirrors Create semantics (current state is the item itself); the pre-delete tombstone stays until a later delete supersedes it or purge removes it.
- **Concurrency retry** lives in `SaveWithHistoryRetryAsync` (one retry, then `Conflict`), per the spec's locked decision.
- **Mobile branch** of the entity pages does not get the History action in v1 — desktop grid only (spec silent on mobile; cheap follow-up).
- Existing handler tests gain a constructor argument (`EntityHistoryRecorder`) in Tasks 4–5; that is expected churn, not scope creep.

## Unresolved Questions

- CLI history/restore verbs: deferred (spec open question — recommend defer).
- Silent link-dropping on restore/revert: v1 is silent; snackbar note listed as cheap follow-up in spec.
- Recycle Bin mobile layout: table-only OK for v1?

