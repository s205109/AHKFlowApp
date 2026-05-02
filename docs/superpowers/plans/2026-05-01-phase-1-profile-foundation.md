# Phase 1 — Profile Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the `Profile` aggregate (CRUD API + UI) so subsequent phases can attach hotkeys/hotstrings to profiles via M2M and generate per-profile `.ahk` scripts.

**Architecture:** Clean Architecture flow — `ProfilesController` → MediatR → `AppDbContext`. Mirrors the existing Hotstring slice exactly; no new framework concepts. Default profile is seeded lazily inside `ListProfilesQueryHandler` the first time a user lists profiles. Header/footer templates live on the Profile row; in the UI they expand below the row as monospace textareas.

**Tech Stack:** .NET 10, EF Core (SQL Server), MediatR, Ardalis.Result, FluentValidation, MudBlazor, xUnit + FluentAssertions + NSubstitute + Testcontainers, bUnit.

**Maps to backlog:** 024 + 025 (combined per the design spec).
**Spec:** `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 1).

**Branch:** `feature/028-phase-1-profile-foundation` (rename from current `feature/028-phase-1-profile-foundation-plan` once the plan lands, OR start a new branch when execution begins).

---

## File structure

### New files

| Path | Purpose |
|---|---|
| `src/Backend/AHKFlowApp.Domain/Entities/Profile.cs` | Aggregate root |
| `src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs` | Default `HeaderTemplate` + `FooterTemplate` strings |
| `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/ProfileConfiguration.cs` | EF config + indexes |
| `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_AddProfiles.cs` | Migration |
| `src/Backend/AHKFlowApp.Application/DTOs/ProfileDto.cs` | API DTOs (record types) |
| `src/Backend/AHKFlowApp.Application/Validation/ProfileRules.cs` | FluentValidation extension methods |
| `src/Backend/AHKFlowApp.Application/Mapping/ProfileMappings.cs` | Entity → DTO extension |
| `src/Backend/AHKFlowApp.Application/Commands/Profiles/CreateProfileCommand.cs` | Command + validator + handler |
| `src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs` | Command + validator + handler |
| `src/Backend/AHKFlowApp.Application/Commands/Profiles/DeleteProfileCommand.cs` | Command + handler |
| `src/Backend/AHKFlowApp.Application/Queries/Profiles/GetProfileQuery.cs` | Query + handler |
| `src/Backend/AHKFlowApp.Application/Queries/Profiles/ListProfilesQuery.cs` | Query + handler (lazy seeding lives here) |
| `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs` | REST surface |
| `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/ProfileDto.cs` | UI-side DTOs |
| `src/Frontend/AHKFlowApp.UI.Blazor/Services/ProfilesApiClient.cs` | Typed HTTP client |
| `src/Frontend/AHKFlowApp.UI.Blazor/Validation/ProfileEditModel.cs` | Inline-edit view model |
| `tests/AHKFlowApp.Domain.Tests/Entities/ProfileTests.cs` | Domain unit tests |
| `tests/AHKFlowApp.TestUtilities/Builders/ProfileBuilder.cs` | Test data builder |
| `tests/AHKFlowApp.Application.Tests/Profiles/ProfileDbFixture.cs` | Testcontainers fixture (collection) |
| `tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandValidatorTests.cs` | Validator tests |
| `tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandValidatorTests.cs` | Validator tests |
| `tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandHandlerTests.cs` | Handler tests |
| `tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandHandlerTests.cs` | Handler tests |
| `tests/AHKFlowApp.Application.Tests/Profiles/DeleteProfileCommandHandlerTests.cs` | Handler tests |
| `tests/AHKFlowApp.Application.Tests/Profiles/GetProfileQueryHandlerTests.cs` | Handler tests |
| `tests/AHKFlowApp.Application.Tests/Profiles/ListProfilesQueryHandlerTests.cs` | Handler tests (incl. seeding) |
| `tests/AHKFlowApp.API.Tests/Profiles/ProfilesEndpointsTests.cs` | API integration tests |
| `tests/AHKFlowApp.UI.Blazor.Tests/Pages/ProfilesPageTests.cs` | bUnit page tests |

### Modified files

| Path | Change |
|---|---|
| `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs` | Add `DbSet<Profile> Profiles` |
| `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` | Add `Profiles` DbSet |
| `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor` | Replace stub with full page |
| `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor` | Verify Profiles nav link exists (should already; just confirm) |
| `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs` | Register `IProfilesApiClient` |

---

## Tasks

### Task 1: `Profile` domain entity + unit tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Entities/Profile.cs`
- Create: `tests/AHKFlowApp.Domain.Tests/Entities/ProfileTests.cs`

- [ ] **Step 1.1 — Write the failing tests**

```csharp
// tests/AHKFlowApp.Domain.Tests/Entities/ProfileTests.cs
using AHKFlowApp.Domain.Entities;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class ProfileTests
{
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
    private readonly Guid _ownerOid = Guid.Parse("11111111-1111-1111-1111-111111111111");

    [Fact]
    public void Create_assigns_id_owner_name_templates_default_flag_and_timestamps()
    {
        Profile profile = Profile.Create(
            ownerOid: _ownerOid,
            name: "Work",
            isDefault: true,
            headerTemplate: "; header",
            footerTemplate: "; footer",
            clock: _clock);

        profile.Id.Should().NotBeEmpty();
        profile.OwnerOid.Should().Be(_ownerOid);
        profile.Name.Should().Be("Work");
        profile.IsDefault.Should().BeTrue();
        profile.HeaderTemplate.Should().Be("; header");
        profile.FooterTemplate.Should().Be("; footer");
        profile.CreatedAt.Should().Be(_clock.GetUtcNow());
        profile.UpdatedAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public void Update_changes_name_templates_and_bumps_updated_at_only()
    {
        Profile profile = Profile.Create(_ownerOid, "Work", true, "h", "f", _clock);
        DateTimeOffset originalCreated = profile.CreatedAt;

        _clock.Advance(TimeSpan.FromHours(1));
        profile.Update("Personal", "h2", "f2", _clock);

        profile.Name.Should().Be("Personal");
        profile.HeaderTemplate.Should().Be("h2");
        profile.FooterTemplate.Should().Be("f2");
        profile.CreatedAt.Should().Be(originalCreated);
        profile.UpdatedAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public void MarkDefault_true_sets_flag()
    {
        Profile profile = Profile.Create(_ownerOid, "Work", false, "", "", _clock);
        profile.MarkDefault(true, _clock);
        profile.IsDefault.Should().BeTrue();
    }

    [Fact]
    public void MarkDefault_bumps_updated_at()
    {
        Profile profile = Profile.Create(_ownerOid, "Work", false, "", "", _clock);
        _clock.Advance(TimeSpan.FromMinutes(5));
        profile.MarkDefault(true, _clock);
        profile.UpdatedAt.Should().Be(_clock.GetUtcNow());
    }
}
```

- [ ] **Step 1.2 — Run the tests; expect compile failure (`Profile` does not exist)**

```powershell
dotnet test tests/AHKFlowApp.Domain.Tests --filter "FullyQualifiedName~ProfileTests"
```

- [ ] **Step 1.3 — Implement the entity**

```csharp
// src/Backend/AHKFlowApp.Domain/Entities/Profile.cs
namespace AHKFlowApp.Domain.Entities;

public sealed class Profile
{
    private Profile()
    {
        Name = string.Empty;
        HeaderTemplate = string.Empty;
        FooterTemplate = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Name { get; private set; }
    public bool IsDefault { get; private set; }
    public string HeaderTemplate { get; private set; }
    public string FooterTemplate { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public static Profile Create(
        Guid ownerOid,
        string name,
        bool isDefault,
        string headerTemplate,
        string footerTemplate,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Profile
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Name = name,
            IsDefault = isDefault,
            HeaderTemplate = headerTemplate,
            FooterTemplate = footerTemplate,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public void Update(string name, string headerTemplate, string footerTemplate, TimeProvider clock)
    {
        Name = name;
        HeaderTemplate = headerTemplate;
        FooterTemplate = footerTemplate;
        UpdatedAt = clock.GetUtcNow();
    }

    public void MarkDefault(bool isDefault, TimeProvider clock)
    {
        IsDefault = isDefault;
        UpdatedAt = clock.GetUtcNow();
    }
}
```

- [ ] **Step 1.4 — Re-run tests; expect PASS**

```powershell
dotnet test tests/AHKFlowApp.Domain.Tests --filter "FullyQualifiedName~ProfileTests"
```

- [ ] **Step 1.5 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Domain/Entities/Profile.cs `
        tests/AHKFlowApp.Domain.Tests/Entities/ProfileTests.cs
git commit -m "feat(domain): add Profile entity"
```

---

### Task 2: Default header/footer template constants

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs`

- [ ] **Step 2.1 — Add the constants file**

```csharp
// src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs
namespace AHKFlowApp.Domain.Constants;

public static class DefaultProfileTemplates
{
    public const string Header = """
        #Requires AutoHotkey v2.0
        #SingleInstance Force
        SetCapsLockState "AlwaysOff"
        SetWorkingDir A_ScriptDir

        """;

    public const string Footer = "";
}
```

- [ ] **Step 2.2 — Build**

```powershell
dotnet build src/Backend/AHKFlowApp.Domain
```

- [ ] **Step 2.3 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs
git commit -m "feat(domain): add default profile header/footer templates"
```

---

### Task 3: EF configuration + DbContext wiring

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/ProfileConfiguration.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`

- [ ] **Step 3.1 — Add `Profiles` to the abstraction**

Edit `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs` — add the line `DbSet<Profile> Profiles { get; }` next to the existing DbSets:

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<Hotstring> Hotstrings { get; }
    DbSet<Hotkey> Hotkeys { get; }
    DbSet<Profile> Profiles { get; }
    DbSet<UserPreference> UserPreferences { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

- [ ] **Step 3.2 — Add `Profiles` to the concrete `AppDbContext`**

Edit `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` — add the property:

```csharp
public DbSet<Profile> Profiles => Set<Profile>();
```

(Place between the existing `Hotkeys` and `UserPreferences` lines.)

- [ ] **Step 3.3 — Add the EF configuration**

```csharp
// src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/ProfileConfiguration.cs
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class ProfileConfiguration : IEntityTypeConfiguration<Profile>
{
    public void Configure(EntityTypeBuilder<Profile> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(x => x.IsDefault).IsRequired();

        builder.Property(x => x.HeaderTemplate)
            .IsRequired()
            .HasMaxLength(8000);

        builder.Property(x => x.FooterTemplate)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // Name unique per owner.
        builder.HasIndex(x => new { x.OwnerOid, x.Name })
            .IsUnique()
            .HasDatabaseName("IX_Profile_Owner_Name");

        // At most one default profile per owner (filtered unique index).
        builder.HasIndex(x => new { x.OwnerOid, x.IsDefault })
            .IsUnique()
            .HasFilter("[IsDefault] = 1")
            .HasDatabaseName("IX_Profile_Owner_DefaultOnly");
    }
}
```

- [ ] **Step 3.4 — Build everything**

```powershell
dotnet build --configuration Release
```

Expected: build succeeds. (Migration not yet generated; existing DbContext use sites compile because `Profiles` is just an additional member.)

- [ ] **Step 3.5 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs `
        src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs `
        src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/ProfileConfiguration.cs
git commit -m "feat(infra): add Profile EF configuration and DbSet"
```

---

### Task 4: EF migration

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_AddProfiles.cs` (auto-generated)

- [ ] **Step 4.1 — Generate the migration**

```powershell
dotnet ef migrations add AddProfiles `
  --project src/Backend/AHKFlowApp.Infrastructure `
  --startup-project src/Backend/AHKFlowApp.API
```

- [ ] **Step 4.2 — Inspect the generated `Up` method**

Verify it:
- Creates a `Profiles` table with all columns at the configured types/lengths.
- Adds index `IX_Profile_Owner_Name` (unique).
- Adds filtered unique index `IX_Profile_Owner_DefaultOnly` with filter `[IsDefault] = 1`.
- Adds index on `OwnerOid` (non-unique).

If anything's off, fix the `ProfileConfiguration` and regenerate.

- [ ] **Step 4.3 — Apply locally and confirm**

```powershell
dotnet ef database update `
  --project src/Backend/AHKFlowApp.Infrastructure `
  --startup-project src/Backend/AHKFlowApp.API
```

Expected: no errors; `Profiles` table created.

- [ ] **Step 4.4 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Infrastructure/Migrations/
git commit -m "feat(infra): add Profiles migration"
```

---

### Task 5: Application DTOs

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/DTOs/ProfileDto.cs`

- [ ] **Step 5.1 — Add the DTOs**

```csharp
// src/Backend/AHKFlowApp.Application/DTOs/ProfileDto.cs
namespace AHKFlowApp.Application.DTOs;

public sealed record ProfileDto(
    Guid Id,
    string Name,
    bool IsDefault,
    string HeaderTemplate,
    string FooterTemplate,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record CreateProfileDto(
    string Name,
    string? HeaderTemplate = null,
    string? FooterTemplate = null,
    bool IsDefault = false);

public sealed record UpdateProfileDto(
    string Name,
    string HeaderTemplate,
    string FooterTemplate,
    bool IsDefault);
```

- [ ] **Step 5.2 — Build**

```powershell
dotnet build src/Backend/AHKFlowApp.Application
```

- [ ] **Step 5.3 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/DTOs/ProfileDto.cs
git commit -m "feat(app): add Profile DTOs"
```

---

### Task 6: Validation rules

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Validation/ProfileRules.cs`

- [ ] **Step 6.1 — Add the rules**

```csharp
// src/Backend/AHKFlowApp.Application/Validation/ProfileRules.cs
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class ProfileRules
{
    public const int NameMaxLength = 100;
    public const int HeaderTemplateMaxLength = 8000;
    public const int FooterTemplateMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidName<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Name is required.")
          .MaximumLength(NameMaxLength).WithMessage($"Name must be {NameMaxLength} characters or fewer.")
          .Must(n => n is not null && n.Length == n.Trim().Length)
              .WithMessage("Name must not have leading or trailing whitespace.");

    public static IRuleBuilderOptions<T, string> ValidHeaderTemplate<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.MaximumLength(HeaderTemplateMaxLength)
          .WithMessage($"HeaderTemplate must be {HeaderTemplateMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, string> ValidFooterTemplate<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.MaximumLength(FooterTemplateMaxLength)
          .WithMessage($"FooterTemplate must be {FooterTemplateMaxLength} characters or fewer.");
}
```

- [ ] **Step 6.2 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Validation/ProfileRules.cs
git commit -m "feat(app): add Profile validation rules"
```

---

### Task 7: Mapping extension

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Mapping/ProfileMappings.cs`

- [ ] **Step 7.1 — Add the mapping**

```csharp
// src/Backend/AHKFlowApp.Application/Mapping/ProfileMappings.cs
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class ProfileMappings
{
    public static ProfileDto ToDto(this Profile p) => new(
        p.Id,
        p.Name,
        p.IsDefault,
        p.HeaderTemplate,
        p.FooterTemplate,
        p.CreatedAt,
        p.UpdatedAt);
}
```

- [ ] **Step 7.2 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Mapping/ProfileMappings.cs
git commit -m "feat(app): add Profile entity-to-DTO mapping"
```

---

### Task 8: ProfileBuilder (test util)

**Files:**
- Create: `tests/AHKFlowApp.TestUtilities/Builders/ProfileBuilder.cs`

- [ ] **Step 8.1 — Add the builder**

```csharp
// tests/AHKFlowApp.TestUtilities/Builders/ProfileBuilder.cs
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class ProfileBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _name = "Default";
    private bool _isDefault = true;
    private string _headerTemplate = "";
    private string _footerTemplate = "";
    private TimeProvider _clock = TimeProvider.System;

    public ProfileBuilder WithOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }
    public ProfileBuilder WithName(string name) { _name = name; return this; }
    public ProfileBuilder AsDefault(bool isDefault = true) { _isDefault = isDefault; return this; }
    public ProfileBuilder WithHeader(string header) { _headerTemplate = header; return this; }
    public ProfileBuilder WithFooter(string footer) { _footerTemplate = footer; return this; }
    public ProfileBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public Profile Build() => Profile.Create(
        _ownerOid, _name, _isDefault, _headerTemplate, _footerTemplate, _clock);
}
```

- [ ] **Step 8.2 — Commit**

```powershell
git add tests/AHKFlowApp.TestUtilities/Builders/ProfileBuilder.cs
git commit -m "test: add ProfileBuilder"
```

---

### Task 9: Profile DB fixture (Testcontainers)

**Files:**
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/ProfileDbFixture.cs`

- [ ] **Step 9.1 — Add the fixture (mirrors `HotstringDbFixture`)**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/ProfileDbFixture.cs
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

public sealed class ProfileDbFixture : IAsyncLifetime
{
    private readonly SqlContainerFixture _sql = new();

    public string ConnectionString => _sql.ConnectionString;

    public async Task InitializeAsync()
    {
        await _sql.InitializeAsync();
        await using AppDbContext ctx = CreateContext();
        await ctx.Database.MigrateAsync();
    }

    public Task DisposeAsync() => _sql.DisposeAsync();

    public AppDbContext CreateContext()
    {
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(ConnectionString)
            .Options;
        return new AppDbContext(options);
    }
}

[CollectionDefinition("ProfileDb")]
public sealed class ProfileDbCollection : ICollectionFixture<ProfileDbFixture>;
```

- [ ] **Step 9.2 — Commit**

```powershell
git add tests/AHKFlowApp.Application.Tests/Profiles/ProfileDbFixture.cs
git commit -m "test: add ProfileDbFixture for integration tests"
```

---

### Task 10: `CreateProfileCommand` + validator + handler + tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Profiles/CreateProfileCommand.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandValidatorTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandHandlerTests.cs`

- [ ] **Step 10.1 — Write the validator tests**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandValidatorTests.cs
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.TestHelper;

namespace AHKFlowApp.Application.Tests.Profiles;

public sealed class CreateProfileCommandValidatorTests
{
    private readonly CreateProfileCommandValidator _sut = new();

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Name_required(string name)
    {
        var result = _sut.TestValidate(new CreateProfileCommand(new CreateProfileDto(name)));
        result.ShouldHaveValidationErrorFor(x => x.Input.Name);
    }

    [Fact]
    public void Name_too_long()
    {
        var result = _sut.TestValidate(
            new CreateProfileCommand(new CreateProfileDto(new string('x', 101))));
        result.ShouldHaveValidationErrorFor(x => x.Input.Name);
    }

    [Fact]
    public void Header_too_long()
    {
        var result = _sut.TestValidate(
            new CreateProfileCommand(new CreateProfileDto("ok", HeaderTemplate: new string('x', 8001))));
        result.ShouldHaveValidationErrorFor(x => x.Input.HeaderTemplate);
    }

    [Fact]
    public void Footer_too_long()
    {
        var result = _sut.TestValidate(
            new CreateProfileCommand(new CreateProfileDto("ok", FooterTemplate: new string('x', 4001))));
        result.ShouldHaveValidationErrorFor(x => x.Input.FooterTemplate);
    }

    [Fact]
    public void Valid_input_passes()
    {
        var result = _sut.TestValidate(new CreateProfileCommand(new CreateProfileDto("Work")));
        result.IsValid.Should().BeTrue();
    }
}
```

- [ ] **Step 10.2 — Run; expect compile failure (`CreateProfileCommand` does not exist yet)**

- [ ] **Step 10.3 — Write the handler tests**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class CreateProfileCommandHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

    [Fact]
    public async Task Creates_profile_for_authenticated_user()
    {
        await using var ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);

        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("Work")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Work");
        (await ctx.Profiles.CountAsync(p => p.OwnerOid == _ownerOid)).Should().Be(1);
    }

    [Fact]
    public async Task Returns_conflict_on_duplicate_name_for_same_owner()
    {
        await using var ctx = fx.CreateContext();
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").Build());
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("Work")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using var ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("Work")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task IsDefault_true_clears_existing_default_for_owner()
    {
        await using var ctx = fx.CreateContext();
        Profile existing = new ProfileBuilder().WithOwner(_ownerOid).WithName("Old").AsDefault(true).Build();
        ctx.Profiles.Add(existing);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("New", IsDefault: true)), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        Profile reloaded = await ctx.Profiles.AsNoTracking().FirstAsync(p => p.Id == existing.Id);
        reloaded.IsDefault.Should().BeFalse();
    }
}
```

- [ ] **Step 10.4 — Implement the command + validator + handler**

```csharp
// src/Backend/AHKFlowApp.Application/Commands/Profiles/CreateProfileCommand.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record CreateProfileCommand(CreateProfileDto Input) : IRequest<Result<ProfileDto>>;

public sealed class CreateProfileCommandValidator : AbstractValidator<CreateProfileCommand>
{
    public CreateProfileCommandValidator()
    {
        RuleFor(x => x.Input.Name).ValidName();
        RuleFor(x => x.Input.HeaderTemplate ?? "").ValidHeaderTemplate();
        RuleFor(x => x.Input.FooterTemplate ?? "").ValidFooterTemplate();
    }
}

internal sealed class CreateProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<CreateProfileCommand, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> Handle(CreateProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateProfileDto input = request.Input;

        bool nameTaken = await db.Profiles.AnyAsync(
            p => p.OwnerOid == ownerOid && p.Name == input.Name, ct);
        if (nameTaken)
            return Result.Conflict($"A profile named '{input.Name}' already exists.");

        if (input.IsDefault)
        {
            await foreach (Profile existing in db.Profiles
                .Where(p => p.OwnerOid == ownerOid && p.IsDefault)
                .AsAsyncEnumerable()
                .WithCancellation(ct))
            {
                existing.MarkDefault(false, clock);
            }
        }

        var profile = Profile.Create(
            ownerOid,
            input.Name,
            input.IsDefault,
            input.HeaderTemplate ?? DefaultProfileTemplates.Header,
            input.FooterTemplate ?? DefaultProfileTemplates.Footer,
            clock);

        db.Profiles.Add(profile);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict($"A profile named '{input.Name}' already exists.");
        }

        return Result.Success(profile.ToDto());
    }

    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

- [ ] **Step 10.5 — Run all the new tests; expect PASS**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --filter "FullyQualifiedName~CreateProfileCommand"
```

- [ ] **Step 10.6 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Commands/Profiles/CreateProfileCommand.cs `
        tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandValidatorTests.cs `
        tests/AHKFlowApp.Application.Tests/Profiles/CreateProfileCommandHandlerTests.cs
git commit -m "feat(app): add CreateProfileCommand + tests"
```

---

### Task 11: `UpdateProfileCommand` + validator + handler + tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandValidatorTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandHandlerTests.cs`

- [ ] **Step 11.1 — Write tests covering: success path, unknown id → NotFound, duplicate name → Conflict, IsDefault=true clears other defaults, cross-tenant id → NotFound, unauthorized when no Oid.**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class UpdateProfileCommandHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

    private UpdateProfileCommandHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(oid ?? _ownerOid);
        return new UpdateProfileCommandHandler(ctx, user, _clock);
    }

    [Fact]
    public async Task Updates_existing_profile()
    {
        await using var ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        var sut = CreateSut(ctx);
        var result = await sut.Handle(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("Work2", "h", "f", true)),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Work2");
        result.Value.HeaderTemplate.Should().Be("h");
    }

    [Fact]
    public async Task Returns_404_for_unknown_id()
    {
        await using var ctx = fx.CreateContext();
        var sut = CreateSut(ctx);
        var result = await sut.Handle(
            new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto("x", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_404_for_other_users_profile()
    {
        await using var ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(Guid.NewGuid()).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        var sut = CreateSut(ctx);
        var result = await sut.Handle(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("x", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_conflict_on_duplicate_name()
    {
        await using var ctx = fx.CreateContext();
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(_ownerOid).WithName("A").Build());
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).WithName("B").Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        var sut = CreateSut(ctx);
        var result = await sut.Handle(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("A", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Setting_IsDefault_true_clears_existing_default()
    {
        await using var ctx = fx.CreateContext();
        Profile a = new ProfileBuilder().WithOwner(_ownerOid).WithName("A").AsDefault(true).Build();
        Profile b = new ProfileBuilder().WithOwner(_ownerOid).WithName("B").AsDefault(false).Build();
        ctx.Profiles.AddRange(a, b);
        await ctx.SaveChangesAsync();

        var sut = CreateSut(ctx);
        await sut.Handle(
            new UpdateProfileCommand(b.Id, new UpdateProfileDto("B", "", "", true)),
            CancellationToken.None);

        Profile aReloaded = await ctx.Profiles.AsNoTracking().FirstAsync(x => x.Id == a.Id);
        Profile bReloaded = await ctx.Profiles.AsNoTracking().FirstAsync(x => x.Id == b.Id);
        aReloaded.IsDefault.Should().BeFalse();
        bReloaded.IsDefault.Should().BeTrue();
    }
}
```

- [ ] **Step 11.2 — Implement command + validator + handler**

```csharp
// src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record UpdateProfileCommand(Guid Id, UpdateProfileDto Input) : IRequest<Result<ProfileDto>>;

public sealed class UpdateProfileCommandValidator : AbstractValidator<UpdateProfileCommand>
{
    public UpdateProfileCommandValidator()
    {
        RuleFor(x => x.Input.Name).ValidName();
        RuleFor(x => x.Input.HeaderTemplate).ValidHeaderTemplate();
        RuleFor(x => x.Input.FooterTemplate).ValidFooterTemplate();
    }
}

internal sealed class UpdateProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateProfileCommand, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> Handle(UpdateProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        UpdateProfileDto input = request.Input;

        if (input.Name != profile.Name)
        {
            bool nameTaken = await db.Profiles.AnyAsync(
                p => p.OwnerOid == ownerOid && p.Id != profile.Id && p.Name == input.Name, ct);
            if (nameTaken)
                return Result.Conflict($"A profile named '{input.Name}' already exists.");
        }

        if (input.IsDefault && !profile.IsDefault)
        {
            await foreach (Profile other in db.Profiles
                .Where(p => p.OwnerOid == ownerOid && p.IsDefault && p.Id != profile.Id)
                .AsAsyncEnumerable()
                .WithCancellation(ct))
            {
                other.MarkDefault(false, clock);
            }
        }

        profile.Update(input.Name, input.HeaderTemplate, input.FooterTemplate, clock);
        if (input.IsDefault != profile.IsDefault)
            profile.MarkDefault(input.IsDefault, clock);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict($"A profile named '{input.Name}' already exists.");
        }

        return Result.Success(profile.ToDto());
    }

    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

- [ ] **Step 11.3 — Write the validator tests file (mirror CreateProfileCommandValidatorTests, swap to UpdateProfileCommand and UpdateProfileDto). Run all; expect PASS.**

- [ ] **Step 11.4 — Commit**

```powershell
git add src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs `
        tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommand*.cs
git commit -m "feat(app): add UpdateProfileCommand + tests"
```

---

### Task 12: `DeleteProfileCommand` + handler + tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Commands/Profiles/DeleteProfileCommand.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/DeleteProfileCommandHandlerTests.cs`

> **Phase 1 scope note:** Phase 2 (M2M) will guard `DELETE` against profiles with hotkey/hotstring associations. Phase 1 cannot enforce that yet — `Hotstring.ProfileId` is still a nullable scalar with no FK. Phase 1's delete simply removes the row. Phase 2 will harden this by adding the 409 guard once the junction tables exist.

- [ ] **Step 12.1 — Write tests: success deletes row, unknown id → NotFound, other-user id → NotFound, unauthorized when no Oid.**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/DeleteProfileCommandHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class DeleteProfileCommandHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    [Fact]
    public async Task Deletes_owned_profile()
    {
        await using var ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user);

        Result result = await sut.Handle(new DeleteProfileCommand(p.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        (await ctx.Profiles.AnyAsync(x => x.Id == p.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task Returns_404_for_other_users_profile()
    {
        await using var ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(Guid.NewGuid()).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user);

        Result result = await sut.Handle(new DeleteProfileCommand(p.Id), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_404_for_unknown_id()
    {
        await using var ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user);

        Result result = await sut.Handle(new DeleteProfileCommand(Guid.NewGuid()), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 12.2 — Implement command + handler**

```csharp
// src/Backend/AHKFlowApp.Application/Commands/Profiles/DeleteProfileCommand.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record DeleteProfileCommand(Guid Id) : IRequest<Result>;

internal sealed class DeleteProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<DeleteProfileCommand, Result>
{
    public async Task<Result> Handle(DeleteProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        db.Profiles.Remove(profile);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
```

- [ ] **Step 12.3 — Run; expect PASS. Commit.**

```powershell
git add src/Backend/AHKFlowApp.Application/Commands/Profiles/DeleteProfileCommand.cs `
        tests/AHKFlowApp.Application.Tests/Profiles/DeleteProfileCommandHandlerTests.cs
git commit -m "feat(app): add DeleteProfileCommand + tests"
```

---

### Task 13: `GetProfileQuery` + `ListProfilesQuery` + handlers + tests

**Files:**
- Create: `src/Backend/AHKFlowApp.Application/Queries/Profiles/GetProfileQuery.cs`
- Create: `src/Backend/AHKFlowApp.Application/Queries/Profiles/ListProfilesQuery.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/GetProfileQueryHandlerTests.cs`
- Create: `tests/AHKFlowApp.Application.Tests/Profiles/ListProfilesQueryHandlerTests.cs`

> The list handler is responsible for **lazy default-profile seeding**: if the authenticated user has zero profiles, it creates one (`Name="Default"`, `IsDefault=true`, header from `DefaultProfileTemplates.Header`, footer empty), commits, and returns it.

- [ ] **Step 13.1 — Write `GetProfileQueryHandlerTests`**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/GetProfileQueryHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class GetProfileQueryHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    [Fact]
    public async Task Returns_owned_profile()
    {
        await using var ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).WithName("X").Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new GetProfileQueryHandler(ctx, user);

        Result<ProfileDto> result = await sut.Handle(new GetProfileQuery(p.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(p.Id);
    }

    [Fact]
    public async Task Returns_404_for_other_users_profile()
    {
        await using var ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(Guid.NewGuid()).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new GetProfileQueryHandler(ctx, user);

        Result<ProfileDto> result = await sut.Handle(new GetProfileQuery(p.Id), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 13.2 — Write `ListProfilesQueryHandlerTests`**

```csharp
// tests/AHKFlowApp.Application.Tests/Profiles/ListProfilesQueryHandlerTests.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class ListProfilesQueryHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

    private ListProfilesQueryHandler CreateSut(AppDbContext ctx)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return new ListProfilesQueryHandler(ctx, user, _clock);
    }

    [Fact]
    public async Task First_call_seeds_default_profile_when_user_has_none()
    {
        await using var ctx = fx.CreateContext();
        var sut = CreateSut(ctx);

        Result<IReadOnlyList<ProfileDto>> result = await sut.Handle(new ListProfilesQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        ProfileDto seeded = result.Value[0];
        seeded.Name.Should().Be("Default");
        seeded.IsDefault.Should().BeTrue();
        seeded.HeaderTemplate.Should().Be(DefaultProfileTemplates.Header);
        seeded.FooterTemplate.Should().Be(DefaultProfileTemplates.Footer);
        (await ctx.Profiles.CountAsync(p => p.OwnerOid == _ownerOid)).Should().Be(1);
    }

    [Fact]
    public async Task Returns_users_profiles_ordered_default_first_then_name()
    {
        await using var ctx = fx.CreateContext();
        ctx.Profiles.AddRange(
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Zeta").AsDefault(false).Build(),
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Alpha").AsDefault(false).Build(),
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Mid").AsDefault(true).Build(),
            new ProfileBuilder().WithOwner(Guid.NewGuid()).WithName("OtherUser").Build());
        await ctx.SaveChangesAsync();

        var sut = CreateSut(ctx);
        Result<IReadOnlyList<ProfileDto>> result = await sut.Handle(new ListProfilesQuery(), CancellationToken.None);

        result.Value.Select(p => p.Name).Should().Equal("Mid", "Alpha", "Zeta");
    }
}
```

- [ ] **Step 13.3 — Implement queries**

```csharp
// src/Backend/AHKFlowApp.Application/Queries/Profiles/GetProfileQuery.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Profiles;

public sealed record GetProfileQuery(Guid Id) : IRequest<Result<ProfileDto>>;

internal sealed class GetProfileQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetProfileQuery, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> Handle(GetProfileQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.AsNoTracking().FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        return profile is null ? Result.NotFound() : Result.Success(profile.ToDto());
    }
}
```

```csharp
// src/Backend/AHKFlowApp.Application/Queries/Profiles/ListProfilesQuery.cs
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Profiles;

public sealed record ListProfilesQuery : IRequest<Result<IReadOnlyList<ProfileDto>>>;

internal sealed class ListProfilesQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<ListProfilesQuery, Result<IReadOnlyList<ProfileDto>>>
{
    public async Task<Result<IReadOnlyList<ProfileDto>>> Handle(ListProfilesQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool any = await db.Profiles.AnyAsync(p => p.OwnerOid == ownerOid, ct);
        if (!any)
        {
            var seeded = Profile.Create(
                ownerOid,
                name: "Default",
                isDefault: true,
                headerTemplate: DefaultProfileTemplates.Header,
                footerTemplate: DefaultProfileTemplates.Footer,
                clock: clock);
            db.Profiles.Add(seeded);
            await db.SaveChangesAsync(ct);
        }

        List<ProfileDto> items = await db.Profiles
            .AsNoTracking()
            .Where(p => p.OwnerOid == ownerOid)
            .OrderByDescending(p => p.IsDefault)
            .ThenBy(p => p.Name)
            .Select(p => new ProfileDto(
                p.Id, p.Name, p.IsDefault, p.HeaderTemplate, p.FooterTemplate, p.CreatedAt, p.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success<IReadOnlyList<ProfileDto>>(items);
    }
}
```

- [ ] **Step 13.4 — Run; expect PASS. Commit.**

```powershell
git add src/Backend/AHKFlowApp.Application/Queries/Profiles/ `
        tests/AHKFlowApp.Application.Tests/Profiles/GetProfileQueryHandlerTests.cs `
        tests/AHKFlowApp.Application.Tests/Profiles/ListProfilesQueryHandlerTests.cs
git commit -m "feat(app): add Profile queries with lazy default seeding"
```

---

### Task 14: `ProfilesController` + API integration tests

**Files:**
- Create: `src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs`
- Create: `tests/AHKFlowApp.API.Tests/Profiles/ProfilesEndpointsTests.cs`

- [ ] **Step 14.1 — Add the controller**

```csharp
// src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs
using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
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
public sealed class ProfilesController(IMediator mediator) : ControllerBase
{
    /// <summary>List the current user's profiles. Lazily seeds a default profile on first call.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ProfileDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ProfileDto>>> List(CancellationToken ct) =>
        (await mediator.Send(new ListProfilesQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Get a profile by id.</summary>
    [HttpGet("{id:guid}", Name = "GetProfile")]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProfileDto>> Get(Guid id, CancellationToken ct) =>
        (await mediator.Send(new GetProfileQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Create a new profile for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ProfileDto>> Create([FromBody] CreateProfileDto dto, CancellationToken ct)
    {
        Result<ProfileDto> result = await mediator.Send(new CreateProfileCommand(dto), ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetProfile", new { id = result.Value.Id }, result.Value)
            : result.ToProblemActionResult(this);
    }

    /// <summary>Update a profile.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ProfileDto>> Update(Guid id, [FromBody] UpdateProfileDto dto, CancellationToken ct) =>
        (await mediator.Send(new UpdateProfileCommand(id, dto), ct)).ToProblemActionResult(this);

    /// <summary>Delete a profile.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        Result result = await mediator.Send(new DeleteProfileCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
}
```

- [ ] **Step 14.2 — Add API integration tests**

Pattern: copy `HotstringsEndpointsTests` shape (uses `CustomWebApplicationFactory` + `TestAuthHandler` + `TestUserBuilder`). Cover: GET list happy path + first-call seeds default, GET 404 for cross-user id, POST 201 with `Location` header, POST 400 on invalid name, POST 409 on duplicate, PUT 200 + body, PUT 404 unknown id, DELETE 204, DELETE 404 cross-user, 401 without auth.

```csharp
// tests/AHKFlowApp.API.Tests/Profiles/ProfilesEndpointsTests.cs
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Auth;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Profiles;

[Collection("Api")]
public sealed class ProfilesEndpointsTests(CustomWebApplicationFactory factory)
{
    [Fact]
    public async Task GET_list_seeds_default_on_first_call()
    {
        Guid oid = Guid.NewGuid();
        HttpClient client = factory.CreateAuthenticatedClient(new TestUserBuilder().WithOid(oid).Build());

        HttpResponseMessage response = await client.GetAsync("/api/v1/profiles");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        IReadOnlyList<ProfileDto>? items = await response.Content.ReadFromJsonAsync<IReadOnlyList<ProfileDto>>();
        items.Should().ContainSingle().Which.IsDefault.Should().BeTrue();
    }

    [Fact]
    public async Task POST_creates_profile_returns_201_with_location()
    {
        HttpClient client = factory.CreateAuthenticatedClient(new TestUserBuilder().Build());
        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Work"));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();
    }

    [Fact]
    public async Task POST_returns_409_on_duplicate_name()
    {
        HttpClient client = factory.CreateAuthenticatedClient(new TestUserBuilder().Build());
        await client.PostAsJsonAsync("/api/v1/profiles", new CreateProfileDto("Work"));

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Work"));
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task POST_returns_400_when_name_blank()
    {
        HttpClient client = factory.CreateAuthenticatedClient(new TestUserBuilder().Build());
        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto(""));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GET_id_returns_404_for_other_user_profile()
    {
        Guid otherOid = Guid.NewGuid();
        HttpClient otherClient = factory.CreateAuthenticatedClient(new TestUserBuilder().WithOid(otherOid).Build());
        HttpResponseMessage created = await otherClient.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Theirs"));
        ProfileDto theirProfile = (await created.Content.ReadFromJsonAsync<ProfileDto>())!;

        HttpClient meClient = factory.CreateAuthenticatedClient(new TestUserBuilder().Build());
        HttpResponseMessage response = await meClient.GetAsync($"/api/v1/profiles/{theirProfile.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task PUT_updates_returns_200()
    {
        HttpClient client = factory.CreateAuthenticatedClient(new TestUserBuilder().Build());
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Work"));
        ProfileDto p = (await created.Content.ReadFromJsonAsync<ProfileDto>())!;

        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/profiles/{p.Id}",
            new UpdateProfileDto("Work2", "h", "f", true));
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        ProfileDto updated = (await response.Content.ReadFromJsonAsync<ProfileDto>())!;
        updated.Name.Should().Be("Work2");
    }

    [Fact]
    public async Task DELETE_returns_204()
    {
        HttpClient client = factory.CreateAuthenticatedClient(new TestUserBuilder().Build());
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("ToDelete"));
        ProfileDto p = (await created.Content.ReadFromJsonAsync<ProfileDto>())!;

        HttpResponseMessage response = await client.DeleteAsync($"/api/v1/profiles/{p.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task GET_list_unauthenticated_returns_401()
    {
        HttpClient client = factory.CreateClient();
        HttpResponseMessage response = await client.GetAsync("/api/v1/profiles");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

- [ ] **Step 14.3 — Run all backend tests; expect PASS**

```powershell
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release
dotnet test tests/AHKFlowApp.API.Tests --configuration Release
```

- [ ] **Step 14.4 — Commit**

```powershell
git add src/Backend/AHKFlowApp.API/Controllers/ProfilesController.cs `
        tests/AHKFlowApp.API.Tests/Profiles/ProfilesEndpointsTests.cs
git commit -m "feat(api): add ProfilesController + integration tests"
```

---

### Task 15: Frontend `ProfileDto` + `ProfilesApiClient`

**Files:**
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/ProfileDto.cs`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Services/ProfilesApiClient.cs`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Services/ProfilesApiClientTests.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`

- [ ] **Step 15.1 — Add UI DTOs (mirror `Application` records)**

```csharp
// src/Frontend/AHKFlowApp.UI.Blazor/DTOs/ProfileDto.cs
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record ProfileDto(
    Guid Id,
    string Name,
    bool IsDefault,
    string HeaderTemplate,
    string FooterTemplate,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record CreateProfileDto(
    string Name,
    string? HeaderTemplate = null,
    string? FooterTemplate = null,
    bool IsDefault = false);

public sealed record UpdateProfileDto(
    string Name,
    string HeaderTemplate,
    string FooterTemplate,
    bool IsDefault);
```

- [ ] **Step 15.2 — Add the API client (extend `ApiClientBase` like `HotstringsApiClient`)**

```csharp
// src/Frontend/AHKFlowApp.UI.Blazor/Services/ProfilesApiClient.cs
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IProfilesApiClient
{
    Task<ApiResult<IReadOnlyList<ProfileDto>>> ListAsync(CancellationToken ct = default);
    Task<ApiResult<ProfileDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<ProfileDto>> CreateAsync(CreateProfileDto dto, CancellationToken ct = default);
    Task<ApiResult<ProfileDto>> UpdateAsync(Guid id, UpdateProfileDto dto, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}

public sealed class ProfilesApiClient(IHttpClientFactory factory) : ApiClientBase, IProfilesApiClient
{
    private const string ClientName = "AHKFlowAppApi";
    private const string BaseRoute = "api/v1/profiles";

    public Task<ApiResult<IReadOnlyList<ProfileDto>>> ListAsync(CancellationToken ct = default) =>
        SendAsync<IReadOnlyList<ProfileDto>>(
            factory.CreateClient(ClientName),
            HttpMethod.Get, BaseRoute, ct: ct);

    public Task<ApiResult<ProfileDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<ProfileDto>(
            factory.CreateClient(ClientName),
            HttpMethod.Get, $"{BaseRoute}/{id}", ct: ct);

    public Task<ApiResult<ProfileDto>> CreateAsync(CreateProfileDto dto, CancellationToken ct = default) =>
        SendAsync<ProfileDto>(
            factory.CreateClient(ClientName),
            HttpMethod.Post, BaseRoute, JsonContent.Create(dto), ct: ct);

    public Task<ApiResult<ProfileDto>> UpdateAsync(Guid id, UpdateProfileDto dto, CancellationToken ct = default) =>
        SendAsync<ProfileDto>(
            factory.CreateClient(ClientName),
            HttpMethod.Put, $"{BaseRoute}/{id}", JsonContent.Create(dto), ct: ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendAsync(
            factory.CreateClient(ClientName),
            HttpMethod.Delete, $"{BaseRoute}/{id}", ct: ct);
}
```

> **Note for executor:** match the exact `ApiClientBase` send signatures used by `HotstringsApiClient`. If they differ (e.g., a different overload pattern), copy that file's pattern verbatim and replace `Hotstring` with `Profile`.

- [ ] **Step 15.3 — Register the client in `Program.cs`**

In `src/Frontend/AHKFlowApp.UI.Blazor/Program.cs`, find the existing `IHotstringsApiClient` registration and add immediately below it:

```csharp
builder.Services.AddScoped<IProfilesApiClient, ProfilesApiClient>();
```

- [ ] **Step 15.4 — Add `ProfilesApiClientTests` (mirror `HotstringsApiClientTests`)**

Cover: `ListAsync` deserializes JSON, `CreateAsync` posts body and reads back DTO, `UpdateAsync` PUTs, `DeleteAsync` returns success on 204, error path returns `ApiResult` with `Problem`.

- [ ] **Step 15.5 — Run UI tests; expect PASS. Commit.**

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~ProfilesApiClient"
git add src/Frontend/AHKFlowApp.UI.Blazor/DTOs/ProfileDto.cs `
        src/Frontend/AHKFlowApp.UI.Blazor/Services/ProfilesApiClient.cs `
        src/Frontend/AHKFlowApp.UI.Blazor/Program.cs `
        tests/AHKFlowApp.UI.Blazor.Tests/Services/ProfilesApiClientTests.cs
git commit -m "feat(ui): add Profiles API client + DTOs"
```

---

### Task 16: `Pages/Profiles.razor` rebuild + bUnit tests

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor`
- Create: `src/Frontend/AHKFlowApp.UI.Blazor/Validation/ProfileEditModel.cs`
- Create: `tests/AHKFlowApp.UI.Blazor.Tests/Pages/ProfilesPageTests.cs`

**UX shape (matches the spec):**
- `MudTable` listing profiles, columns: **Default (radio), Name, Created, Updated, Actions**.
- Add / Reload buttons in the header bar (mirrors Hotstrings).
- Inline row edit for `Name` + `IsDefault` (radio); the row also has an "Expand" toggle that reveals two large monospace `MudTextArea`s for `HeaderTemplate` (Lines=20) and `FooterTemplate` (Lines=10) below the row, in a `ChildRowContent` template.
- The "Default" column is a single radio across rows: clicking radio on row N issues `PUT /profiles/{N}` with `IsDefault=true`. Server clears the previous default. Reload table after success.
- Delete action: `IDialogService.ShowMessageBoxAsync` confirmation, then `DELETE /profiles/{id}`.
- Validation: `Name` required, ≤100 chars, no leading/trailing whitespace. `HeaderTemplate` ≤8000. `FooterTemplate` ≤4000.

> **Convention check:** `src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md` allows inline `MudTable` editing for tabular CRUD with ≤6 short fields and prescribes `IDialogService.ShowAsync<T>` for "non-trivial layouts (multi-section, tabs, file upload, etc.)". The header/footer textareas are large but live in an *expand-row*, not a separate dialog — this matches the spec's "expand-row textareas for header/footer" wording. If the executor disagrees with the convention call, switch to a dialog-based editor and document the deviation in the PR.

- [ ] **Step 16.1 — Add the edit model**

```csharp
// src/Frontend/AHKFlowApp.UI.Blazor/Validation/ProfileEditModel.cs
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class ProfileEditModel
{
    public string Name { get; set; } = "";
    public string HeaderTemplate { get; set; } = "";
    public string FooterTemplate { get; set; } = "";
    public bool IsDefault { get; set; }

    public static ProfileEditModel FromDto(ProfileDto dto) => new()
    {
        Name = dto.Name,
        HeaderTemplate = dto.HeaderTemplate,
        FooterTemplate = dto.FooterTemplate,
        IsDefault = dto.IsDefault,
    };

    public CreateProfileDto ToCreateDto() =>
        new(Name, HeaderTemplate, FooterTemplate, IsDefault);

    public UpdateProfileDto ToUpdateDto() =>
        new(Name, HeaderTemplate, FooterTemplate, IsDefault);
}
```

- [ ] **Step 16.2 — Replace `Pages/Profiles.razor` with the full implementation**

Use `Pages/Hotstrings.razor` as the template; replace the model and field set. Key adaptations:

```razor
@page "/profiles"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor
@using Microsoft.AspNetCore.Components.Authorization
@implements IDisposable

<PageTitle>Profiles</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Profiles</MudText>

<MudPaper Class="pa-4">
    <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="2" Wrap="Wrap.Wrap" Class="mb-4">
        <MudButton Class="add-profile" Variant="Variant.Filled" Color="Color.Primary"
                   StartIcon="@Icons.Material.Filled.Add" OnClick="StartAddAsync"
                   Disabled="@(!_isAuthenticated || _editing.ContainsKey(Guid.Empty))">
            Add
        </MudButton>
        <MudButton Class="reload-profiles" Variant="Variant.Filled" Color="Color.Secondary"
                   StartIcon="@Icons.Material.Filled.Refresh" OnClick="ReloadAsync"
                   Disabled="@(!_isAuthenticated || _loading)">
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
            <MudTh Style="width:160px">Created</MudTh>
            <MudTh Style="width:160px">Updated</MudTh>
            <MudTh Style="width:200px">Actions</MudTh>
        </HeaderContent>
        <RowTemplate>
            @if (_editing.TryGetValue(context.Id, out var edit))
            {
                bool showErrors = _commitAttempted.Contains(context.Id);
                string? nameError = showErrors ? ValidateName(edit.Name) : null;
                <MudTd>
                    <MudCheckBox T="bool" @bind-Value="edit.IsDefault" />
                </MudTd>
                <MudTd>
                    <MudTextField @bind-Value="edit.Name"
                                  Validation="@(new Func<string, string?>(ValidateName))"
                                  Error="@(nameError is not null)" ErrorText="@nameError"
                                  Immediate="true" MaxLength="100"
                                  UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "profile-name-input" })" />
                </MudTd>
                <MudTd>@(context.Id == Guid.Empty ? "—" : context.CreatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm"))</MudTd>
                <MudTd>@(context.Id == Guid.Empty ? "—" : context.UpdatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm"))</MudTd>
                <MudTd>
                    <MudIconButton Class="commit-edit" Icon="@Icons.Material.Filled.Check"
                                   Color="Color.Success" OnClick="() => CommitEditAsync(context.Id)" />
                    <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.Close"
                                   Color="Color.Default" OnClick="() => CancelEditAsync(context.Id)" />
                </MudTd>
            }
            else
            {
                <MudTd><MudIcon Icon="@(context.IsDefault ? Icons.Material.Filled.Star : Icons.Material.Outlined.StarBorder)" /></MudTd>
                <MudTd>@context.Name</MudTd>
                <MudTd>@context.CreatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm")</MudTd>
                <MudTd>@context.UpdatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm")</MudTd>
                <MudTd>
                    <MudIconButton Class="toggle-expand" Icon="@(IsExpanded(context.Id) ? Icons.Material.Filled.ExpandLess : Icons.Material.Filled.ExpandMore)"
                                   OnClick="() => ToggleExpand(context.Id)" />
                    <MudIconButton Class="start-edit" Icon="@Icons.Material.Filled.Edit"
                                   OnClick="() => StartEdit(context)" />
                    <MudIconButton Class="delete" Icon="@Icons.Material.Filled.Delete" Color="Color.Error"
                                   OnClick="() => DeleteAsync(context)" />
                </MudTd>
            }
        </RowTemplate>
        <ChildRowContent>
            @if (IsExpanded(context.Id) || _editing.ContainsKey(context.Id))
            {
                ProfileEditModel? edit = _editing.GetValueOrDefault(context.Id);
                <td colspan="5">
                    <MudPaper Elevation="0" Class="pa-3" Style="background-color: var(--mud-palette-background-grey);">
                        <MudText Typo="Typo.subtitle2">Header template</MudText>
                        @if (edit is not null)
                        {
                            <MudTextField @bind-Value="edit.HeaderTemplate"
                                          T="string" Lines="20" Variant="Variant.Outlined"
                                          MaxLength="8000" Style="font-family: monospace;"
                                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "profile-header-input" })" />
                        }
                        else
                        {
                            <pre style="white-space: pre-wrap; font-family: monospace;">@context.HeaderTemplate</pre>
                        }
                        <MudText Typo="Typo.subtitle2" Class="mt-3">Footer template</MudText>
                        @if (edit is not null)
                        {
                            <MudTextField @bind-Value="edit.FooterTemplate"
                                          T="string" Lines="10" Variant="Variant.Outlined"
                                          MaxLength="4000" Style="font-family: monospace;"
                                          UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "profile-footer-input" })" />
                        }
                        else
                        {
                            <pre style="white-space: pre-wrap; font-family: monospace;">@context.FooterTemplate</pre>
                        }
                    </MudPaper>
                </td>
            }
        </ChildRowContent>
        <NoRecordsContent><MudText>No profiles yet.</MudText></NoRecordsContent>
    </MudTable>
</MudPaper>

@code {
    [CascadingParameter] private Task<AuthenticationState>? AuthState { get; set; }
    [Inject] private IProfilesApiClient Api { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;

    private List<ProfileDto> _profiles = [];
    private readonly Dictionary<Guid, ProfileEditModel> _editing = new();
    private readonly HashSet<Guid> _commitAttempted = [];
    private readonly HashSet<Guid> _expanded = [];
    private bool _isAuthenticated;
    private bool _loading;
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
        ApiResult<IReadOnlyList<ProfileDto>> result = await Api.ListAsync(_cts.Token);
        _loading = false;

        if (!result.IsSuccess)
        {
            _loadError = ApiErrorMessageFactory.Build(result.Status, result.Problem);
            _profiles = [];
            return;
        }

        _profiles = [.. result.Value!];
        if (_editing.ContainsKey(Guid.Empty))
        {
            // Keep the draft row at the top while re-listing.
            _profiles.Insert(0, new ProfileDto(Guid.Empty, "", false, "", "", DateTimeOffset.MinValue, DateTimeOffset.MinValue));
        }
    }

    private async Task StartAddAsync()
    {
        _editing[Guid.Empty] = new ProfileEditModel();
        await ReloadAsync();
    }

    private void StartEdit(ProfileDto dto) =>
        _editing[dto.Id] = ProfileEditModel.FromDto(dto);

    private async Task CancelEditAsync(Guid id)
    {
        _editing.Remove(id);
        _commitAttempted.Remove(id);
        if (id == Guid.Empty) await ReloadAsync();
    }

    private bool IsExpanded(Guid id) => _expanded.Contains(id);
    private void ToggleExpand(Guid id)
    {
        if (!_expanded.Add(id)) _expanded.Remove(id);
    }

    private static string? ValidateName(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "Name is required";
        if (value.Length > 100) return "Name must be 100 characters or fewer";
        if (value.Length != value.Trim().Length) return "Name must not have leading or trailing whitespace";
        return null;
    }

    private async Task CommitEditAsync(Guid id)
    {
        if (!_editing.TryGetValue(id, out ProfileEditModel? edit)) return;
        _commitAttempted.Add(id);
        if (ValidateName(edit.Name) is not null) return;
        _commitAttempted.Remove(id);

        if (id == Guid.Empty)
        {
            ApiResult<ProfileDto> result = await Api.CreateAsync(edit.ToCreateDto(), _cts.Token);
            HandleResult(id, result, "Profile created.");
        }
        else
        {
            ApiResult<ProfileDto> result = await Api.UpdateAsync(id, edit.ToUpdateDto(), _cts.Token);
            HandleResult(id, result, "Profile updated.");
        }
    }

    private async void HandleResult(Guid id, ApiResult<ProfileDto> result, string successMessage)
    {
        if (result.IsSuccess)
        {
            _editing.Remove(id);
            Snackbar.Add(successMessage, Severity.Success);
            await ReloadAsync();
        }
        else
        {
            Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }

    private async Task DeleteAsync(ProfileDto dto)
    {
        bool? confirm = await DialogService.ShowMessageBoxAsync(
            title: "Delete profile?",
            message: $"Delete \"{dto.Name}\"? This cannot be undone.",
            yesText: "Delete", cancelText: "Cancel");
        if (confirm != true) return;

        ApiResult result = await Api.DeleteAsync(dto.Id, _cts.Token);
        if (result.IsSuccess)
        {
            Snackbar.Add("Profile deleted.", Severity.Success);
            await ReloadAsync();
        }
        else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

- [ ] **Step 16.3 — Add bUnit page tests**

`tests/AHKFlowApp.UI.Blazor.Tests/Pages/ProfilesPageTests.cs` should mirror `HotstringsPageTests`. Cover at minimum:
- Page renders header + Add / Reload buttons.
- Renders table rows from a stubbed `IProfilesApiClient`.
- Add → fill name → commit → calls `CreateAsync` once with the right DTO.
- Edit → modify Name → commit → calls `UpdateAsync` once with the right DTO.
- Delete → confirm dialog → calls `DeleteAsync`.
- Toggle expand reveals header/footer textareas in `ChildRowContent`.
- Validation error: blank name shows `Name is required`, commit does not call `CreateAsync`.

Use `NSubstitute.For<IProfilesApiClient>()` and `IDialogService` substitutes. Reuse the `ApiResult` factory helpers from `HotstringsPageTests`.

- [ ] **Step 16.4 — Run UI tests; expect PASS**

```powershell
dotnet test tests/AHKFlowApp.UI.Blazor.Tests --filter "FullyQualifiedName~ProfilesPageTests"
```

- [ ] **Step 16.5 — Commit**

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor `
        src/Frontend/AHKFlowApp.UI.Blazor/Validation/ProfileEditModel.cs `
        tests/AHKFlowApp.UI.Blazor.Tests/Pages/ProfilesPageTests.cs
git commit -m "feat(ui): rebuild Profiles page with inline edit + expand-row templates"
```

---

### Task 17: NavMenu link verification

**Files:**
- Verify: `src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor`

- [ ] **Step 17.1 — Open `Layout/NavMenu.razor` and confirm a `Profiles` link exists pointing to `/profiles` with an appropriate icon (e.g. `Icons.Material.Filled.Folder`). If absent, add one in alphabetical order with the existing siblings.**

- [ ] **Step 17.2 — If a change was made, commit it**

```powershell
git add src/Frontend/AHKFlowApp.UI.Blazor/Layout/NavMenu.razor
git commit -m "feat(ui): add Profiles to NavMenu"
```

---

### Task 18: Full verification + manual smoke

- [ ] **Step 18.1 — Full build + test**

```powershell
dotnet build --configuration Release
dotnet test --configuration Release --no-build
```

Expected: solution builds clean, all tests green.

- [ ] **Step 18.2 — Format check**

```powershell
dotnet format --verify-no-changes
```

If diffs report, run `dotnet format` and amend the last commit.

- [ ] **Step 18.3 — Manual smoke (local stack)**

```powershell
docker compose up --build
```

Then in the browser:
1. Sign in with a test user that has no profiles.
2. Visit `/profiles` — page should render with one auto-seeded "Default" profile, marked default.
3. Click Add, name `Work`, commit. Expect a snackbar success and a new row.
4. Edit `Work`, change name to `Work2`, mark as default. Confirm `Default` star moves from `Default` row to `Work2`.
5. Expand `Work2`, edit header template, commit. Re-expand to verify persistence.
6. Try creating a profile with the duplicate name `Work2` — expect a 409 surfaced as a snackbar error.
7. Delete `Work2` — confirm and verify it's gone.

- [ ] **Step 18.4 — Open the PR**

```powershell
git push -u origin feature/028-phase-1-profile-foundation
gh pr create --title "feat: phase 1 — profile foundation" --body "$(cat <<'EOF'
## Summary
- Adds Profile aggregate (entity, EF config, migration, default header/footer constants).
- ProfilesController with full CRUD; lazy default-profile seeding on first list call.
- Blazor Profiles page rebuild with inline edit + expand-row header/footer textareas.

## Test plan
- [ ] Full backend test suite green (Domain, Application, API).
- [ ] bUnit ProfilesPage tests green.
- [ ] Manual smoke: auto-seed on first sign-in, CRUD, default-flag toggling, header/footer edit persistence.

Closes backlog 024 + 025. Phase 1 of the AHKFlow alignment redesign (`docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md`).
EOF
)"
```

---

## Self-review (run before handoff)

1. **Spec coverage** — Phase 1 ACs from the spec mapped to tasks:
   - Profile entity + EF config + migration → Tasks 1, 3, 4 ✓
   - Default-profile seeding on first sign-in → Task 13 (`ListProfilesQueryHandler`) ✓
   - ProfilesController CRUD → Task 14 ✓
   - UI list + inline edit + expand-row textareas → Task 16 ✓
   - Templates land with the entity (combined 024 + 025) → Tasks 2, 3 (HeaderTemplate/FooterTemplate fields), 14 (DTO carries both) ✓

2. **Placeholder scan** — none found.

3. **Type/name consistency** — `Profile.Create`, `Profile.Update`, `Profile.MarkDefault` used consistently across tasks. `ProfileDto` shape identical between Application and UI projects. `IProfilesApiClient` matches the controller's verb/route surface.

4. **Out of scope (per spec)** — explicit:
   - DELETE 409 guard against attached hotkeys/hotstrings — deferred to Phase 2 (call-out in Task 12).
   - M2M junction tables, "Any" flag, hotstring/hotkey UI changes — Phases 2/3.
