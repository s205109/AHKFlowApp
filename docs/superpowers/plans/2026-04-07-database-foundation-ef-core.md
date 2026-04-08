# Database Foundation (EF Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `TestMessage` entity to validate EF Core migrations end-to-end, with a Testcontainers integration test confirming schema and data persistence.

**Architecture:** Domain entity → `IEntityTypeConfiguration` in Infrastructure → `AppDbContext.DbSet<>` → migration → integration test. `AppDbContext`, DI registration, `SqlContainerFixture`, and development profiles are already in place. The existing empty `Initial` migration is removed and replaced with a single clean `Initial` migration that includes the `TestMessages` table.

**Tech Stack:** EF Core 10 / SQL Server, Testcontainers.MsSql, xUnit + FluentAssertions

---

### Task 1: Create feature branch and remove empty Initial migration

**Files:**
- Delete: `src/Backend/AHKFlowApp.Infrastructure/Migrations/20260403094113_Initial.cs`
- Delete: `src/Backend/AHKFlowApp.Infrastructure/Migrations/20260403094113_Initial.Designer.cs`
- Modify (reset): `src/Backend/AHKFlowApp.Infrastructure/Migrations/AppDbContextModelSnapshot.cs`

- [ ] **Step 1: Create branch from main**

```bash
git checkout main && git pull
git checkout -b feature/007-database-foundation-ef-core
```

- [ ] **Step 2: Revert the empty migration from local dev DB**

```bash
dotnet ef database update 0 \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Expected: `Reverting migration '20260403094113_Initial'. Done.`
(Migration was empty so nothing changes in the DB schema — the `__EFMigrationsHistory` row is removed.)

- [ ] **Step 3: Remove the migration files**

```bash
dotnet ef migrations remove \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Expected: `Done.` — the three migration files are deleted.

- [ ] **Step 4: Verify no migrations remain**

```bash
dotnet ef migrations list \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Expected: `No migrations were found.`

---

### Task 2: Write the failing integration test

**Files:**
- Create: `tests/AHKFlowApp.Infrastructure.Tests/Persistence/TestMessageTests.cs`

- [ ] **Step 1: Write the test**

`CreatedAt` is set explicitly at the call site (no `DateTime.UtcNow` default on the entity). Two facts: one for persistence, one for `CreatedAt`. Both use `MigrateAsync()` — the migration applies successfully but the table does not exist yet, so both will fail at runtime until Task 6 adds the migration.

```csharp
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class TestMessageTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateMigratedContext(string databaseName)
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString) { InitialCatalog = databaseName };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;
        var context = new AppDbContext(options);
        context.Database.Migrate();
        return context;
    }

    [Fact]
    public async Task Add_TestMessage_PersistsMessage()
    {
        // Arrange
        await using AppDbContext context = CreateMigratedContext("TestMessageTests_Persist");
        var message = new TestMessage { Message = "hello", CreatedAt = DateTime.UtcNow };

        // Act
        context.TestMessages.Add(message);
        await context.SaveChangesAsync();

        // Assert
        await using AppDbContext readContext = CreateMigratedContext("TestMessageTests_Persist");
        TestMessage? saved = await readContext.TestMessages.FindAsync(message.Id);
        saved.Should().NotBeNull();
        saved!.Message.Should().Be("hello");
    }

    [Fact]
    public async Task Add_TestMessage_PersistsCreatedAt()
    {
        // Arrange
        await using AppDbContext context = CreateMigratedContext("TestMessageTests_CreatedAt");
        var now = DateTime.UtcNow;
        var message = new TestMessage { Message = "ts-test", CreatedAt = now };

        // Act
        context.TestMessages.Add(message);
        await context.SaveChangesAsync();

        // Assert
        await using AppDbContext readContext = CreateMigratedContext("TestMessageTests_CreatedAt");
        TestMessage? saved = await readContext.TestMessages.FindAsync(message.Id);
        saved!.CreatedAt.Should().BeCloseTo(now, TimeSpan.FromSeconds(1));
    }
}
```

- [ ] **Step 2: Confirm it fails to build (entity doesn't exist yet)**

```bash
dotnet build tests/AHKFlowApp.Infrastructure.Tests --configuration Release
```

Expected: build error — `AHKFlowApp.Domain.Entities.TestMessage` not found

---

### Task 3: Create TestMessage entity in Domain

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Entities/TestMessage.cs`
  *(The `Entities/` directory will be created implicitly by the new file.)*

- [ ] **Step 1: Create the entity**

No `DateTime.UtcNow` default — callers set `CreatedAt` explicitly.

```csharp
namespace AHKFlowApp.Domain.Entities;

public sealed class TestMessage
{
    public int Id { get; set; }
    public string Message { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
```

- [ ] **Step 2: Verify Domain builds**

```bash
dotnet build src/Backend/AHKFlowApp.Domain --configuration Release
```

Expected: Build succeeded, 0 errors

---

### Task 4: Create TestMessageConfiguration in Infrastructure

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/TestMessageConfiguration.cs`

- [ ] **Step 1: Create the configuration**

`AppDbContext` already calls `ApplyConfigurationsFromAssembly` — this file is auto-discovered, no manual registration needed.

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class TestMessageConfiguration : IEntityTypeConfiguration<TestMessage>
{
    public void Configure(EntityTypeBuilder<TestMessage> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Message)
            .IsRequired()
            .HasMaxLength(500);

        builder.Property(x => x.CreatedAt)
            .IsRequired();
    }
}
```

---

### Task 5: Add DbSet to AppDbContext

**Files:**
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`

- [ ] **Step 1: Replace the file contents**

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<TestMessage> TestMessages => Set<TestMessage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
```

- [ ] **Step 2: Build the full solution**

```bash
dotnet build --configuration Release
```

Expected: Build succeeded, 0 errors

- [ ] **Step 3: Run the new tests — red phase (migration not created yet)**

```bash
dotnet test tests/AHKFlowApp.Infrastructure.Tests --configuration Release \
  --filter "FullyQualifiedName~TestMessageTests" --verbosity normal
```

Expected: tests fail — `No migrations were found` or `Invalid object name 'TestMessages'`

---

### Task 6: Create the Initial migration

**Files:**
- Create (auto-generated): `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_Initial.cs`
- Create (auto-generated): `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_Initial.Designer.cs`
- Create (auto-generated): `src/Backend/AHKFlowApp.Infrastructure/Migrations/AppDbContextModelSnapshot.cs`

- [ ] **Step 1: Generate the migration**

```bash
dotnet ef migrations add Initial \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Expected: `Build started... Done. To undo this action, use 'ef migrations remove'`

- [ ] **Step 2: Review the generated migration**

Open the new migration file. Verify it contains:
- `migrationBuilder.CreateTable(name: "TestMessages", ...)` in `Up()`
- Columns: `Id` (int identity), `Message` (nvarchar(500), not null), `CreatedAt` (datetime2, not null)
- `migrationBuilder.DropTable(name: "TestMessages")` in `Down()`

If the migration is empty or incorrect, stop and investigate — do not continue.

- [ ] **Step 3: Apply to local dev database (LocalDB)**

```bash
dotnet ef database update \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API
```

Expected: `Applying migration '..._Initial'. Done.`

---

### Task 7: Verify all tests pass

- [ ] **Step 1: Run Infrastructure.Tests**

```bash
dotnet test tests/AHKFlowApp.Infrastructure.Tests --configuration Release --verbosity normal
```

Expected: 6 tests pass:
- `AppDbContextTests.CanConnect_WhenDatabaseExists_ReturnsTrue`
- `AppDbContextTests.EnsureCreated_AppliesSchemaWithoutError`
- `MigrationTests.Migrate_AppliesPendingMigrationsWithoutError`
- `MigrationTests.Migrate_IsIdempotent_RunsTwiceWithoutError`
- `TestMessageTests.Add_TestMessage_PersistsMessage`
- `TestMessageTests.Add_TestMessage_PersistsCreatedAt`

- [ ] **Step 2: Run full test suite**

```bash
dotnet test --configuration Release --verbosity normal
```

Expected: All tests pass, 0 failures, 0 errors

---

### Task 8: Format and commit

- [ ] **Step 1: Format**

```bash
dotnet format
```

- [ ] **Step 2: Stage and commit**

```bash
git add src/Backend/AHKFlowApp.Domain/Entities/TestMessage.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/TestMessageConfiguration.cs
git add src/Backend/AHKFlowApp.Infrastructure/Migrations/
git add tests/AHKFlowApp.Infrastructure.Tests/Persistence/TestMessageTests.cs
git commit -m "feat: TestMessage entity + migration validates EF Core foundation"
```
