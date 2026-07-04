---
name: dck-ef-core
description: Use when changing AHKFlowApp EF Core, SQL Server, DbContext, migrations, LINQ queries, or persistence behavior.
---

# EF Core (.NET 10 — SQL Server)

## Core Principles

1. **EF Core is the default ORM** — Use it for all data access. No stored procedures, no raw ADO.NET except for diagnostics.
2. **DbContext injected directly into handlers** — No repository pattern. No IAppDbContext interface. EF Core's DbSet already implements repository and unit-of-work. Adding another layer adds indirection without value.
3. **SQL Server only** — LocalDB for local dev, Docker Compose SQL Server for dev containers, Azure SQL for production. `EnableRetryOnFailure()` on all registrations.
4. **Queries should be projections** — Use `.Select()` to project into DTOs. Avoids over-fetching and N+1 issues.
5. **Migrations are code** — Review them, test them, never auto-apply in production.

## Patterns

### DbContext Registration (SQL Server)

```csharp
// Program.cs or Infrastructure DI extension
services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(
        connectionString,
        sql => sql.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(10),
            errorNumbersToAdd: null)));
```

### DbContext Configuration

Use `IEntityTypeConfiguration<T>` to keep entity configs separate and discoverable. No data annotations on entities.

```csharp
// Infrastructure/Persistence/AppDbContext.cs
public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Hotstring> Hotstrings => Set<Hotstring>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

```csharp
// Infrastructure/Persistence/Configurations/HotstringConfiguration.cs
internal sealed class HotstringConfiguration : IEntityTypeConfiguration<Hotstring>
{
    public void Configure(EntityTypeBuilder<Hotstring> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Trigger).HasMaxLength(50).IsRequired();
        builder.Property(x => x.Replacement).HasMaxLength(500).IsRequired();
        builder.HasIndex(x => x.Trigger).IsUnique();
    }
}
```

### Handler Injects DbContext Directly

```csharp
// Application/Queries/GetHotstringHandler.cs — DO inject DbContext directly
internal sealed class GetHotstringHandler(AppDbContext db)
    : IUseCaseHandler<GetHotstringQuery, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(
        GetHotstringQuery request, CancellationToken ct)
    {
        var entity = await db.Hotstrings.FindAsync([request.Id], ct);
        return entity is not null
            ? Result.Success(new HotstringDto(entity.Id, entity.Trigger, entity.Replacement))
            : Result.NotFound();
    }
}
```

### Query Projections (Avoid Over-Fetching)

```csharp
// GOOD — project to DTO, only loads needed columns
var dto = await db.Hotstrings
    .Where(h => h.Id == request.Id)
    .Select(h => new HotstringDto(h.Id, h.Trigger, h.Replacement))
    .FirstOrDefaultAsync(ct);
```

### ExecuteUpdateAsync / ExecuteDeleteAsync

Bulk operations that bypass change tracking for better performance.

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

Use interceptors for cross-cutting concerns like audit trails.

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
// Store enum as string
builder.Property(h => h.Status)
    .HasConversion<string>()
    .HasMaxLength(50);

// Strongly-typed IDs
public readonly record struct HotstringId(int Value);

builder.Property(h => h.Id)
    .HasConversion(id => id.Value, value => new HotstringId(value));
```

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

### Global Query Filters

```csharp
// Soft delete filter
builder.HasQueryFilter(h => !h.IsDeleted);

// Bypass when needed
var all = await db.Hotstrings.IgnoreQueryFilters().ToListAsync(ct);
```

### Testcontainers (SQL Server)

Always use SQL Server Testcontainers for integration tests — never in-memory provider.

```csharp
private readonly MsSqlContainer _mssql = new MsSqlBuilder()
    .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
    .Build();

// In ConfigureWebHost
services.RemoveAll<DbContextOptions<AppDbContext>>();
services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(_mssql.GetConnectionString()));
```

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

// GOOD — use AppDbContext directly in handlers
internal sealed class GetHotstringHandler(AppDbContext db) { }
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
| Standard CRUD | AppDbContext with projections in handler |
| Bulk updates (100+ rows) | `ExecuteUpdateAsync` / `ExecuteDeleteAsync` |
| Hot-path read query | Compiled query |
| Read-only query | `AsNoTracking()`, or project to a DTO |
| Multiple / large `Include`s | `AsSplitQuery()` |
| Existence check | `AnyAsync`, never `CountAsync > 0` |
| Diagnosing a slow query | Log `Microsoft.EntityFrameworkCore.Database.Command` |
| Audit trails | `SaveChangesInterceptor` |
| Soft deletes | Global query filter + interceptor |
| Strongly-typed IDs | Value converter |
| Production migration | Idempotent SQL script, never auto-migrate |
| Integration tests | Testcontainers `MsSqlContainer` |
