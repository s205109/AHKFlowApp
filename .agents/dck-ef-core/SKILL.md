---
name: dck-ef-core
description: Use when changing AHKFlowApp EF Core, SQL Server, DbContext, migrations, LINQ queries, or persistence behavior.
---

# EF Core (.NET 10 — SQL Server)

## Core Principles

1. **EF Core is the default ORM** — Use it for all data access. No stored procedures, no raw ADO.NET except for diagnostics.
2. **`IAppDbContext` injected into handlers** — This project wraps `AppDbContext` behind `IAppDbContext` (`src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`) purely so handler unit tests can substitute it — the interface still exposes `DbSet<T>` properties directly, no per-entity CRUD methods, so it is not a repository. Never add a repository interface on top of it.
3. **SQL Server only** — LocalDB for local dev, Docker Compose SQL Server for dev containers, Azure SQL for production. `EnableRetryOnFailure()` on all registrations.
4. **Queries should be projections** — Use `.Select()` to project into DTOs. Avoids over-fetching and N+1 issues.
5. **Migrations are code** — Review them, test them, never auto-apply in production.

## Patterns

### DbContext Registration (SQL Server)

See `src/Backend/AHKFlowApp.Infrastructure/DependencyInjection.cs:16-21` for the live registration — `AddDbContext<AppDbContext>` with `EnableRetryOnFailure()`, plus a scoped `IAppDbContext` registration that resolves to the same `AppDbContext` instance.

### DbContext Configuration

`AppDbContext` lives at `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`; entity configs live one level down in `Configurations/`, one file per entity, each implementing `IEntityTypeConfiguration<T>`. `Configurations/HotstringConfiguration.cs` is the fullest example — required/max-length properties, an enum-as-int conversion, and a filtered unique index (`HasIndex(...).HasFilter(null)`) for the "one global row per owner+trigger" rule. Follow its shape rather than a simplified one.

### Handler Injects IAppDbContext Directly

`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs` is the live shape: the handler class is named `{Query}Handler` off the full query name (`GetHotstringQueryHandler`, not `GetHotstringHandler`), it takes `IAppDbContext` (not `AppDbContext`) and `ICurrentUser` in its primary constructor, and it loads the entity with `AsNoTracking()` + `Include()` rather than a `.Select()` projection, then maps with an explicit `.ToDto()` extension (`Application/Mapping/`). Follow that shape, not a `.Select()` projection — see below.

### Loading and Mapping (not `.Select()` projection)

Core Principle #4 above ("Queries should be projections") describes the *intent* — avoid over-fetching — but the actual pattern in this codebase is `AsNoTracking()` + `Include()` on the entity, then an explicit `.ToDto()` extension method in `Application/Mapping/`, not an inline `.Select(x => new Dto(...))`. See `GetHotstringQuery.cs` above for the live shape. Reach for `.Select()` projection only if a query needs to avoid loading a large related collection that `.ToDto()` would otherwise touch.

### ExecuteUpdateAsync / ExecuteDeleteAsync

Bulk operations that bypass change tracking for better performance.

_No live example in this codebase yet — nothing here bulk-updates/deletes today. Framework API reference for when that need arises; convert to a pointer at that time instead of trusting this snippet to still be current._

```csharp
// Update without loading entities
await db.Hotstrings
    .Where(h => h.ProfileId == request.ProfileId)
    .ExecuteUpdateAsync(s => s.SetProperty(h => h.IsActive, false), ct);

// Delete without loading entities
await db.Hotstrings
    .Where(h => h.ProfileId == request.ProfileId)
    .ExecuteDeleteAsync(ct);
```

### Interceptors

_No `SaveChangesInterceptor` exists in this codebase. This app's audit trail (`EntityHistory`) is written explicitly inside command handlers, not via an interceptor — see `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/RestoreHotkeyCommand.cs` for the shape. Keep this section as a framework-API reference only; don't imply the project uses interceptors._

```csharp
public sealed class AuditInterceptor(TimeProvider clock) : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken ct = default)
    {
        var context = eventData.Context;
        if (context is null) return ValueTask.FromResult(result);

        var now = clock.GetUtcNow();

        foreach (var entry in context.ChangeTracker.Entries<IAuditable>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    entry.Entity.CreatedAt = now;
                    entry.Entity.UpdatedAt = now;
                    break;
                case EntityState.Modified:
                    entry.Entity.UpdatedAt = now;
                    break;
            }
        }

        return ValueTask.FromResult(result);
    }
}

// Registration with interceptor
services.AddDbContext<AppDbContext>((sp, options) =>
    options
        .UseSqlServer(connectionString, sql => sql.EnableRetryOnFailure(3, TimeSpan.FromSeconds(10), null))
        .AddInterceptors(sp.GetRequiredService<AuditInterceptor>()));
```

### Compiled Queries

Use for hot-path queries that execute frequently with the same shape.

_No live example in this codebase — no compiled query exists today. Framework API reference only._

```csharp
public static class HotstringQueries
{
    public static readonly Func<AppDbContext, int, CancellationToken, Task<HotstringDto?>> GetById =
        EF.CompileAsyncQuery((AppDbContext db, int id, CancellationToken ct) =>
            db.Hotstrings
                .Where(h => h.Id == id)
                .Select(h => new HotstringDto(h.Id, h.Trigger, h.Replacement))
                .FirstOrDefault());
}

// Usage
var dto = await HotstringQueries.GetById(db, request.Id, ct);
```

### Value Converters

```csharp
// Real example: enum stored as int — src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs:35-37
builder.Property(x => x.Kind)
    .IsRequired()
    .HasConversion<int>();
```

_Strongly-typed ID value converters (e.g. a `HotstringId` wrapper) are not used anywhere in this codebase — every ID is a plain `Guid`. Framework API reference only if that changes._

### Migrations Workflow

```bash
# Create a migration
dotnet ef migrations add AddHotstringIndex \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API

# Review the generated migration — ALWAYS review before applying
# Check for data loss, index strategy, constraint names

# Apply to development database
dotnet ef database update \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API

# Generate idempotent SQL script for production
dotnet ef migrations script --idempotent --output migrations.sql
```

### Soft Delete / Recycle Bin (this app does NOT use a global query filter)

This app has no `IsDeleted` flag and no `HasQueryFilter`. Delete/restore is modeled through an `EntityHistory` snapshot table plus explicit commands — see `src/Backend/AHKFlowApp.Application/Commands/Hotkeys/{RestoreHotkeyCommand,PurgeDeletedHotkeyCommand}.cs`. If a future entity needs true soft-delete via a boolean flag, `HasQueryFilter` is still the right EF Core mechanism — but don't describe it as what this app already does.

### Testcontainers (SQL Server)

Always use SQL Server Testcontainers for integration tests — never in-memory provider.

The shared fixture lives in `tests/AHKFlowApp.TestUtilities/Fixtures/`: `SqlContainerFixture.cs` owns the `MsSqlContainer`, `ApiTestFixture.cs` wraps it with a `CustomWebApplicationFactory`. Tests share one container per collection via `[Collection("WebApi")]` — see `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs:12-15` for the live shape. Never spin up a per-test-class `MsSqlContainer` — that is the exact pattern this project already retired once (see issue #220).

### Query Performance

#### Diagnosing Slow Queries

See the actual SQL before optimizing — never guess. Turn on command logging.

```json
// appsettings.Development.json
{
  "Logging": {
    "LogLevel": { "Microsoft.EntityFrameworkCore.Database.Command": "Information" }
  }
}
```

`EnableSensitiveDataLogging()` also prints parameter values — Development only, never Test/Prod.

#### Tracking Modes

Read-only queries don't need change tracking. Disabling it cuts allocations and CPU.

```csharp
// Per-query — for handler reads that never call SaveChanges
var hotstrings = await db.Hotstrings
    .AsNoTracking()
    .Where(h => h.ProfileId == request.ProfileId)
    .ToListAsync(ct);
```

Projecting into a DTO with `.Select()` (the default in this project) is already effectively no-tracking. Reach for `AsNoTrackingWithIdentityResolution()` only when a query can return the same row more than once (e.g. a join that repeats a `Profile`) and you want one shared instance instead of duplicates.

#### Split Queries (avoid cartesian explosion)

A single query with multiple or large `Include`s multiplies rows (cartesian product). Split it into one round-trip per collection.

_No live example in this codebase — no query combines multiple/large `Include`s today. Framework API reference only._

```csharp
var profiles = await db.Profiles
    .Include(p => p.Hotstrings)
    .Include(p => p.Hotkeys)
    .AsSplitQuery()          // one SELECT per Include instead of one giant JOIN
    .ToListAsync(ct);
```

| Scenario | Use |
|---|---|
| Single `Include`, small child set | Single query (default) |
| Multiple `Include`s (cartesian risk) | `AsSplitQuery()` |
| `Include` with large child collections | `AsSplitQuery()` |
| Need one consistent snapshot in a transaction | Single query |

Prefer a projection (`.Select` into a DTO) over `Include` whenever you don't need the tracked entity — it fetches only the columns you use and sidesteps split-vs-single entirely.

#### Common Query Traps

| Trap | Problem | Fix |
|---|---|---|
| `.Count() > 0` for existence | Counts every matching row | `.AnyAsync(ct)` |
| `.Select()` after `.Include()` | The `Include` is silently ignored | Project the related data inside the `Select` |
| `.Contains()` that won't translate | Falls back to client evaluation | `EF.Functions.Like(h.Trigger, $"%{x}%")` |
| `.ToListAsync()` then `.Where()` in C# | Loads the whole table | Filter in the query first (see anti-patterns) |

## Anti-patterns

### Don't Wrap DbContext in a Repository

```csharp
// BAD — unnecessary abstraction that limits EF Core's power
public interface IHotstringRepository
{
    Task<Hotstring?> GetByIdAsync(int id);
    Task AddAsync(Hotstring hotstring);
    Task SaveChangesAsync();
}

// GOOD — use IAppDbContext directly in handlers (see GetHotstringQueryHandler)
internal sealed class GetHotstringQueryHandler(IAppDbContext db, ICurrentUser currentUser) { }
```

### Don't Use Lazy Loading

```csharp
// BAD — causes N+1 queries
options.UseLazyLoadingProxies();

// GOOD — explicit Include or projection
var hotstrings = await db.Hotstrings
    .Include(h => h.Profile)
    .Where(h => h.IsActive)
    .ToListAsync(ct);
```

### Don't Filter in Memory After ToListAsync

```csharp
// BAD — loads ALL rows, filters in C#
var all = await db.Hotstrings.ToListAsync(ct);
var active = all.Where(h => h.IsActive);

// GOOD — filter in the database
var active = await db.Hotstrings.Where(h => h.IsActive).ToListAsync(ct);
```

### Don't Use Count() to Test Existence

```csharp
// BAD — counts every matching row just to compare against zero
if (await db.Hotstrings.Where(h => h.Trigger == trigger).CountAsync(ct) > 0) { }

// GOOD — stops at the first match
if (await db.Hotstrings.AnyAsync(h => h.Trigger == trigger, ct)) { }
```

### Don't Use Npgsql or PostgreSQL

```csharp
// BAD — wrong database provider for this project
options.UseNpgsql(connectionString);

// GOOD — SQL Server with retry
options.UseSqlServer(connectionString, sql => sql.EnableRetryOnFailure(...));
```

## Decision Guide

| Scenario | Recommendation |
|---|---|
| Standard CRUD | `IAppDbContext` with `AsNoTracking()` + `Include()` + `.ToDto()` in handler |
| Bulk updates (100+ rows) | `ExecuteUpdateAsync` / `ExecuteDeleteAsync` (no live example yet) |
| Hot-path read query | Compiled query (no live example yet) |
| Read-only query | `AsNoTracking()`, or map with `.ToDto()` |
| Multiple / large `Include`s | `AsSplitQuery()` (no live example yet) |
| Existence check | `AnyAsync`, never `CountAsync > 0` |
| Diagnosing a slow query | Log `Microsoft.EntityFrameworkCore.Database.Command` |
| Audit trails | Explicit `EntityHistory` writes in the handler (no interceptor) |
| Delete / restore | `EntityHistory` snapshot + explicit commands (no global query filter) |
| Strongly-typed IDs | Not used — every ID is a `Guid` |
| Production migration | Idempotent SQL script, never auto-migrate |
| Integration tests | Testcontainers `MsSqlContainer` |
