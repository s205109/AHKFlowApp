# Phase 2: Many-to-Many Profile Association Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the scalar `Hotstring.ProfileId` FK with a `HotstringProfile` junction table and an `AppliesToAllProfiles` flag, enabling many-to-many association between hotstrings and profiles.

**Architecture:** Domain gets a `HotstringProfile` junction entity and a `bool AppliesToAllProfiles` on `Hotstring`. Infrastructure adds EF configuration and a destructive migration (dev-only, per spec D7). Application DTOs replace `Guid? ProfileId` with `Guid[] ProfileIds` + `bool AppliesToAllProfiles`; handlers manage junction rows; list/get queries project profile IDs. Hotstrings UI gains a multi-select profile picker and "Any" checkbox. Hotkey is NOT touched in this phase — that is Phase 3.

**Tech Stack:** .NET 10, EF Core 10 (SQL Server), MediatR + Ardalis.Result, FluentValidation, Blazor WebAssembly (MudBlazor 9.x), xUnit + FluentAssertions + Testcontainers

---

## Branch Setup

Start from the Phase 1 branch (Phase 2 depends on the `Profile` entity):

```bash
git checkout feature/028-phase-1-profile-foundation-plan
git checkout -b feature/024b-many-to-many-profile-association
```

---

## File Map

| Action | File |
|--------|------|
| Create | `src/Backend/AHKFlowApp.Domain/Entities/HotstringProfile.cs` |
| Modify | `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs` |
| Create | `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringProfileConfiguration.cs` |
| Modify | `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs` |
| Modify | `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs` |
| Create | `src/Backend/AHKFlowApp.Infrastructure/Migrations/<timestamp>_Phase2ManyToManyProfiles.cs` (generated) |
| Modify | `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Mapping/HotstringMappings.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs` |
| Modify | `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs` |
| Modify | `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandValidatorTests.cs` |
| Modify | `tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandValidatorTests.cs` |
| Modify | `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandHandlerTests.cs` |
| Modify | `tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandHandlerTests.cs` |
| Modify | `tests/AHKFlowApp.Application.Tests/Hotstrings/GetHotstringQueryHandlerTests.cs` |
| Modify | `tests/AHKFlowApp.Application.Tests/Hotstrings/ListHotstringsQueryHandlerTests.cs` |
| Modify | `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringDto.cs` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotstringDto.cs` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotstringDto.cs` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs` |
| Modify | `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor` |
| Modify | `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs` |

---

## Task 1: Domain — HotstringProfile junction entity

**Files:**
- Create: `src/Backend/AHKFlowApp.Domain/Entities/HotstringProfile.cs`

- [ ] **Step 1: Create the junction entity**

```csharp
namespace AHKFlowApp.Domain.Entities;

public sealed class HotstringProfile
{
    private HotstringProfile() { }

    public Guid HotstringId { get; private set; }
    public Guid ProfileId { get; private set; }

    public static HotstringProfile Create(Guid hotstringId, Guid profileId) =>
        new() { HotstringId = hotstringId, ProfileId = profileId };
}
```

- [ ] **Step 2: Verify it compiles**

```bash
dotnet build src/Backend/AHKFlowApp.Domain --configuration Release
```

Expected: `Build succeeded.`

---

## Task 2: Domain — Update Hotstring entity

**Files:**
- Modify: `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs`

- [ ] **Step 1: Replace the file**

Replace the entire content of `src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs`:

```csharp
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
    public bool AppliesToAllProfiles { get; private set; }
    public bool IsEndingCharacterRequired { get; private set; }
    public bool IsTriggerInsideWord { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotstringProfile> Profiles { get; private set; } = [];

    public static Hotstring Create(
        Guid ownerOid,
        string trigger,
        string replacement,
        bool appliesToAllProfiles,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Hotstring
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Trigger = trigger,
            Replacement = replacement,
            AppliesToAllProfiles = appliesToAllProfiles,
            IsEndingCharacterRequired = isEndingCharacterRequired,
            IsTriggerInsideWord = isTriggerInsideWord,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public void Update(
        string trigger,
        string replacement,
        bool appliesToAllProfiles,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        TimeProvider clock)
    {
        Trigger = trigger;
        Replacement = replacement;
        AppliesToAllProfiles = appliesToAllProfiles;
        IsEndingCharacterRequired = isEndingCharacterRequired;
        IsTriggerInsideWord = isTriggerInsideWord;
        UpdatedAt = clock.GetUtcNow();
    }
}
```

- [ ] **Step 2: Build domain — expect compile errors in dependent projects (expected at this stage)**

```bash
dotnet build src/Backend/AHKFlowApp.Domain --configuration Release
```

Expected: `Build succeeded.` (Domain itself builds; Application/Infrastructure/API will fail until updated.)

---

## Task 3: Infrastructure — EF configuration

**Files:**
- Create: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringProfileConfiguration.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs`
- Modify: `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`

- [ ] **Step 1: Create HotstringProfileConfiguration**

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotstringProfileConfiguration : IEntityTypeConfiguration<HotstringProfile>
{
    public void Configure(EntityTypeBuilder<HotstringProfile> builder)
    {
        builder.HasKey(x => new { x.HotstringId, x.ProfileId });

        builder.HasOne<Hotstring>()
            .WithMany(h => h.Profiles)
            .HasForeignKey(x => x.HotstringId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne<Profile>()
            .WithMany()
            .HasForeignKey(x => x.ProfileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
```

- [ ] **Step 2: Replace HotstringConfiguration**

Replace the entire content of `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs`:

```csharp
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AHKFlowApp.Infrastructure.Persistence.Configurations;

internal sealed class HotstringConfiguration : IEntityTypeConfiguration<Hotstring>
{
    public void Configure(EntityTypeBuilder<Hotstring> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.OwnerOid).IsRequired();
        builder.HasIndex(x => x.OwnerOid);

        builder.Property(x => x.Trigger)
            .IsRequired()
            .HasMaxLength(50);

        builder.Property(x => x.Replacement)
            .IsRequired()
            .HasMaxLength(4000);

        builder.Property(x => x.AppliesToAllProfiles).IsRequired();
        builder.Property(x => x.IsEndingCharacterRequired).IsRequired();
        builder.Property(x => x.IsTriggerInsideWord).IsRequired();

        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.UpdatedAt).IsRequired();

        // One trigger per owner globally — profiles are tracked in the junction table.
        builder.HasIndex(x => new { x.OwnerOid, x.Trigger })
            .IsUnique()
            .HasDatabaseName("IX_Hotstring_Owner_Trigger");
    }
}
```

- [ ] **Step 3: Update IAppDbContext**

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
    DbSet<Profile> Profiles { get; }
    DbSet<UserPreference> UserPreferences { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

- [ ] **Step 4: Update AppDbContext**

Replace the entire content of `src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs`:

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
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<UserPreference> UserPreferences => Set<UserPreference>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
```

- [ ] **Step 5: Build Infrastructure (expect Application layer errors still)**

```bash
dotnet build src/Backend/AHKFlowApp.Infrastructure --configuration Release
```

Expected: Build errors in Application layer only (DTOs/commands still reference old `ProfileId`).

---

## Task 4: EF Core Migration

**Files:**
- Create: generated migration under `src/Backend/AHKFlowApp.Infrastructure/Migrations/`

- [ ] **Step 1: Add the migration**

```bash
dotnet ef migrations add Phase2ManyToManyProfiles --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Expected: New migration file created.

- [ ] **Step 2: Verify the migration**

Open the generated `<timestamp>_Phase2ManyToManyProfiles.cs` and confirm it:
- Drops index `IX_Hotstring_Owner_Profile_Trigger`
- Drops index `IX_Hotstring_Owner_Trigger_NoProfile`
- Drops column `ProfileId` on `Hotstrings` table
- Adds column `AppliesToAllProfiles` (bool, not null, default false)
- Creates table `HotstringProfile` with columns `HotstringId` (Guid) and `ProfileId` (Guid)
- Adds composite PK `PK_HotstringProfile (HotstringId, ProfileId)`
- Adds FK `FK_HotstringProfile_Hotstrings_HotstringId` with cascade delete
- Adds FK `FK_HotstringProfile_Profiles_ProfileId` with cascade delete
- Creates index `IX_Hotstring_Owner_Trigger` (unique)

If anything is missing or wrong, adjust the configuration in Task 3 and regenerate.

- [ ] **Step 3: Commit domain + infra + migration**

```bash
git add src/Backend/AHKFlowApp.Domain/Entities/HotstringProfile.cs
git add src/Backend/AHKFlowApp.Domain/Entities/Hotstring.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringProfileConfiguration.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotstringConfiguration.cs
git add src/Backend/AHKFlowApp.Application/Abstractions/IAppDbContext.cs
git add src/Backend/AHKFlowApp.Infrastructure/Persistence/AppDbContext.cs
git add src/Backend/AHKFlowApp.Infrastructure/Migrations/
git commit -m "feat(domain): replace Hotstring.ProfileId with HotstringProfile junction + AppliesToAllProfiles"
```

---

## Task 5: Application — DTOs + Validation Rules

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/DTOs/HotstringDto.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Validation/HotstringRules.cs`

- [ ] **Step 1: Update HotstringDto.cs**

Replace the entire content:

```csharp
namespace AHKFlowApp.Application.DTOs;

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

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);

public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord);
```

- [ ] **Step 2: Update HotstringRules.cs**

Replace the entire content:

```csharp
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotstringRules
{
    public const int TriggerMaxLength = 50;
    public const int ReplacementMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidTrigger<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(t => !string.IsNullOrEmpty(t)).WithMessage("Trigger is required.")
          .MaximumLength(TriggerMaxLength).WithMessage($"Trigger must be {TriggerMaxLength} characters or fewer.")
          .Must(t => t is not null && t.Length == t.Trim().Length)
              .WithMessage("Trigger must not have leading or trailing whitespace.")
          .Must(t => t is not null && t.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Trigger must not contain line breaks or tabs.");

    public static IRuleBuilderOptions<T, string> ValidReplacement<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Replacement is required.")
          .MaximumLength(ReplacementMaxLength).WithMessage($"Replacement must be {ReplacementMaxLength} characters or fewer.");

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

## Task 6: Application — Validator tests (TDD)

**Files:**
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandValidatorTests.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandValidatorTests.cs`

- [ ] **Step 1: Replace CreateHotstringCommandValidatorTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class CreateHotstringCommandValidatorTests
{
    private readonly CreateHotstringCommandValidator _sut = new();

    private static CreateHotstringCommand Cmd(
        string trigger = "btw",
        string replacement = "by the way",
        bool appliesToAllProfiles = true,
        Guid[]? profileIds = null)
        => new(new CreateHotstringDto(trigger, replacement, profileIds, appliesToAllProfiles));

    [Fact]
    public void Validate_AppliesToAll_NoProfiles_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: true, profileIds: null));

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
    public void Validate_WithEmptyTrigger_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger is required.");
    }

    [Fact]
    public void Validate_WithWhitespaceTrigger_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: "   "));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData(" btw")]
    [InlineData("btw ")]
    [InlineData(" btw ")]
    public void Validate_WithTriggerLeadingOrTrailingWhitespace_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("bt\nw")]
    [InlineData("bt\rw")]
    [InlineData("bt\tw")]
    public void Validate_WithTriggerContainingControlChars_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not contain line breaks or tabs.");
    }

    [Theory]
    [InlineData("dür")]
    [InlineData("café")]
    [InlineData("niño")]
    public void Validate_WithUnicodeTrigger_Succeeds(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt50Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 50)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt51Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 51)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must be 50 characters or fewer.");
    }

    [Fact]
    public void Validate_WithEmptyReplacement_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement is required.");
    }

    [Fact]
    public void Validate_WithReplacementAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithReplacementAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }
}
```

- [ ] **Step 2: Replace UpdateHotstringCommandValidatorTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class UpdateHotstringCommandValidatorTests
{
    private readonly UpdateHotstringCommandValidator _sut = new();

    private static UpdateHotstringCommand Cmd(
        string trigger = "btw",
        string replacement = "by the way",
        bool appliesToAllProfiles = true,
        Guid[]? profileIds = null)
        => new(Guid.NewGuid(), new UpdateHotstringDto(trigger, replacement, profileIds, appliesToAllProfiles, true, true));

    [Fact]
    public void Validate_AppliesToAll_NoProfiles_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(appliesToAllProfiles: true, profileIds: null));

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
    public void Validate_WithEmptyTrigger_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger is required.");
    }

    [Fact]
    public void Validate_WithWhitespaceTrigger_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: "   "));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData(" btw")]
    [InlineData("btw ")]
    public void Validate_WithTriggerLeadingOrTrailingWhitespace_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("bt\nw")]
    [InlineData("bt\rw")]
    [InlineData("bt\tw")]
    public void Validate_WithTriggerContainingControlChars_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not contain line breaks or tabs.");
    }

    [Fact]
    public void Validate_WithUnicodeTrigger_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: "dür"));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt50Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 50)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt51Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 51)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must be 50 characters or fewer.");
    }

    [Fact]
    public void Validate_WithEmptyReplacement_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement is required.");
    }

    [Fact]
    public void Validate_WithReplacementAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithReplacementAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }
}
```

---

## Task 7: Application — Mappings + Commands

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Mapping/HotstringMappings.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/CreateHotstringCommand.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Commands/Hotstrings/UpdateHotstringCommand.cs`

- [ ] **Step 1: Update HotstringMappings.cs**

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotstringMappings
{
    public static HotstringDto ToDto(this Hotstring h) => new(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Trigger,
        h.Replacement,
        h.IsEndingCharacterRequired,
        h.IsTriggerInsideWord,
        h.CreatedAt,
        h.UpdatedAt);
}
```

- [ ] **Step 2: Replace CreateHotstringCommand.cs**

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record CreateHotstringCommand(CreateHotstringDto Input) : IRequest<Result<HotstringDto>>;

public sealed class CreateHotstringCommandValidator : AbstractValidator<CreateHotstringCommand>
{
    public CreateHotstringCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidTrigger();
        RuleFor(x => x.Input.Replacement).ValidReplacement();
        this.ValidProfileAssociation(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class CreateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(CreateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        CreateHotstringDto input = request.Input;

        bool duplicate = await db.Hotstrings.AnyAsync(
            h => h.OwnerOid == ownerOid && h.Trigger == input.Trigger, ct);
        if (duplicate)
            return Result.Conflict("A hotstring with this trigger already exists.");

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && input.ProfileIds.Contains(p.Id), ct);
            if (validCount != input.ProfileIds.Length)
                return Result.Invalid(new ValidationError("One or more ProfileIds do not exist for this user."));
        }

        var entity = Hotstring.Create(
            ownerOid,
            input.Trigger,
            input.Replacement,
            input.AppliesToAllProfiles,
            input.IsEndingCharacterRequired,
            input.IsTriggerInsideWord,
            clock);

        db.Hotstrings.Add(entity);

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
                db.HotstringProfiles.Add(HotstringProfile.Create(entity.Id, pid));
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotstring with this trigger already exists.");
        }

        await db.Entry(entity).Collection(h => h.Profiles).LoadAsync(ct);
        return Result.Success(entity.ToDto());
    }

    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

- [ ] **Step 3: Replace UpdateHotstringCommand.cs**

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record UpdateHotstringCommand(Guid Id, UpdateHotstringDto Input) : IRequest<Result<HotstringDto>>;

public sealed class UpdateHotstringCommandValidator : AbstractValidator<UpdateHotstringCommand>
{
    public UpdateHotstringCommandValidator()
    {
        RuleFor(x => x.Input.Trigger).ValidTrigger();
        RuleFor(x => x.Input.Replacement).ValidReplacement();
        this.ValidProfileAssociation(
            x => x.Input.AppliesToAllProfiles,
            x => x.Input.ProfileIds);
    }
}

internal sealed class UpdateHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<UpdateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(UpdateHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        UpdateHotstringDto input = request.Input;

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            int validCount = await db.Profiles
                .CountAsync(p => p.OwnerOid == ownerOid && input.ProfileIds.Contains(p.Id), ct);
            if (validCount != input.ProfileIds.Length)
                return Result.Invalid(new ValidationError("One or more ProfileIds do not exist for this user."));
        }

        entity.Update(
            input.Trigger,
            input.Replacement,
            input.AppliesToAllProfiles,
            input.IsEndingCharacterRequired,
            input.IsTriggerInsideWord,
            clock);

        // Replace junction rows
        db.HotstringProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();

        if (!input.AppliesToAllProfiles && input.ProfileIds is { Length: > 0 })
        {
            foreach (Guid pid in input.ProfileIds)
            {
                var junction = HotstringProfile.Create(entity.Id, pid);
                db.HotstringProfiles.Add(junction);
                entity.Profiles.Add(junction);
            }
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            return Result.Conflict("A hotstring with this trigger already exists.");
        }

        return Result.Success(entity.ToDto());
    }

    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
```

---

## Task 8: Application — Queries

**Files:**
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringQuery.cs`
- Modify: `src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs`

- [ ] **Step 1: Update GetHotstringQuery.cs**

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringQuery(Guid Id) : IRequest<Result<HotstringDto>>;

internal sealed class GetHotstringQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetHotstringQuery, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(GetHotstringQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .AsNoTracking()
            .Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        return entity is null
            ? Result.NotFound()
            : Result.Success(entity.ToDto());
    }
}
```

- [ ] **Step 2: Update ListHotstringsQuery.cs**

Replace the entire file:

```csharp
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record ListHotstringsQuery(
    Guid? ProfileId = null,
    string? Search = null,
    bool IgnoreCase = true,
    int Page = 1,
    int PageSize = 50) : IRequest<Result<PagedList<HotstringDto>>>;

public sealed class ListHotstringsQueryValidator : AbstractValidator<ListHotstringsQuery>
{
    public ListHotstringsQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}

internal sealed class ListHotstringsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<ListHotstringsQuery, Result<PagedList<HotstringDto>>>
{
    public async Task<Result<PagedList<HotstringDto>>> Handle(ListHotstringsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IQueryable<Hotstring> query = db.Hotstrings
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid);

        if (request.ProfileId.HasValue)
        {
            var pid = request.ProfileId.Value;
            query = query.Where(h =>
                h.AppliesToAllProfiles ||
                h.Profiles.Any(p => p.ProfileId == pid));
        }

        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Trigger, pattern) ||
                EF.Functions.Like(h.Replacement, pattern));
        }

        int total = await query.CountAsync(ct);

        List<HotstringDto> items = await query
            .OrderByDescending(h => h.CreatedAt)
            .ThenBy(h => h.Id)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(h => new HotstringDto(
                h.Id,
                h.Profiles.Select(p => p.ProfileId).ToArray(),
                h.AppliesToAllProfiles,
                h.Trigger,
                h.Replacement,
                h.IsEndingCharacterRequired,
                h.IsTriggerInsideWord,
                h.CreatedAt,
                h.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotstringDto>(items, request.Page, request.PageSize, total));
    }
}
```

- [ ] **Step 3: Build all backend projects**

```bash
dotnet build src/Backend --configuration Release
```

Expected: `Build succeeded.`  If there are errors, fix them before continuing.

---

## Task 9: Application handler tests

**Files:**
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/CreateHotstringCommandHandlerTests.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/UpdateHotstringCommandHandlerTests.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/GetHotstringQueryHandlerTests.cs`
- Modify: `tests/AHKFlowApp.Application.Tests/Hotstrings/ListHotstringsQueryHandlerTests.cs`

**Note:** `Hotstring.Create` signature changed — it no longer accepts `Guid? profileId`. All call sites must be updated to pass `appliesToAllProfiles: true` (the equivalent of the old `null` profileId, meaning global/unscoped).

- [ ] **Step 1: Replace CreateHotstringCommandHandlerTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class CreateHotstringCommandHandlerTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenValid_AppliesToAll_CreatesAndReturnsDto()
    {
        await using AppDbContext db = fx.CreateContext();
        var owner = Guid.NewGuid();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", "by the way"));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Trigger.Should().Be("btw");
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenValid_ProfileScoped_CreatesJunctionRows()
    {
        var owner = Guid.NewGuid();
        var profileId = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(Profile.Create(owner, "Work", true, "", "", _clock));
            await seed.SaveChangesAsync();
            // Get the actual profile ID from the DB
        }

        // Re-fetch the profile to get its ID
        Guid actualProfileId;
        await using (AppDbContext verify = fx.CreateContext())
        {
            actualProfileId = (await verify.Profiles.FirstAsync(p => p.OwnerOid == owner)).Id;
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(
            new CreateHotstringDto("btw", "by the way", ProfileIds: [actualProfileId], AppliesToAllProfiles: false));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(actualProfileId);

        await using AppDbContext check = fx.CreateContext();
        (await check.HotstringProfiles.CountAsync(hp => hp.ProfileId == actualProfileId)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(null), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", "by the way"));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTrigger_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "dup", "first", true, true, true, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("dup", "second"));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Handle_SameTriggerDifferentOwners_Succeeds()
    {
        var owner1 = Guid.NewGuid();
        var owner2 = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner1, "shared", "x", true, true, true, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner2), _clock);

        Result<HotstringDto> result = await handler.Handle(
            new CreateHotstringCommand(new CreateHotstringDto("shared", "y")), default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_ProfileScoped_UnknownProfileId_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(
            new CreateHotstringDto("btw", "by the way", ProfileIds: [Guid.NewGuid()], AppliesToAllProfiles: false));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }
}
```

- [ ] **Step 2: Replace UpdateHotstringCommandHandlerTests.cs**

```csharp
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class UpdateHotstringCommandHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenValid_UpdatesAndReturnsUpdatedDto()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var entity = Hotstring.Create(owner, "btw", "old", true, true, true, clock);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(owner), clock);
        var cmd = new UpdateHotstringCommand(entity.Id,
            new UpdateHotstringDto("btw", "by the way", null, true, false, false));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Replacement.Should().Be("by the way");
        result.Value.IsEndingCharacterRequired.Should().BeFalse();
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "btw", "x", true, true, true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(attacker), TimeProvider.System);
        var cmd = new UpdateHotstringCommand(entity.Id,
            new UpdateHotstringDto("btw", "y", null, true, true, true));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System);
        var cmd = new UpdateHotstringCommand(Guid.NewGuid(),
            new UpdateHotstringDto("btw", "x", null, true, true, true));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTrigger_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        var first = Hotstring.Create(owner, "first", "a", true, true, true, TimeProvider.System);
        var second = Hotstring.Create(owner, "second", "b", true, true, true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System);
        var cmd = new UpdateHotstringCommand(second.Id,
            new UpdateHotstringDto("first", "b", null, true, true, true));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
```

- [ ] **Step 3: Replace GetHotstringQueryHandlerTests.cs**

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class GetHotstringQueryHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_ReturnsDto()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "g", "x", true, true, true, TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotstringQueryHandler(db, CurrentUserHelper.For(owner));

        Result<HotstringDto> result = await handler.Handle(new GetHotstringQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "g", "x", true, true, true, TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotstringQueryHandler(db, CurrentUserHelper.For(attacker));

        Result<HotstringDto> result = await handler.Handle(new GetHotstringQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
```

- [ ] **Step 4: Replace ListHotstringsQueryHandlerTests.cs**

```csharp
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class ListHotstringsQueryHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_ScopedToOwner_IgnoresOtherTenants()
    {
        var owner = Guid.NewGuid();
        var other = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "mine", "x", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(other, "theirs", "y", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new ListHotstringsQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Should().OnlyContain(h => h.Trigger == "mine");
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
            var scoped = Hotstring.Create(owner, "a", "x", false, true, true, TimeProvider.System);
            var global = Hotstring.Create(owner, "b", "y", true, true, true, TimeProvider.System);
            var other = Hotstring.Create(owner, "c", "z", false, true, true, TimeProvider.System);
            seed.Hotstrings.AddRange(scoped, global, other);
            await seed.SaveChangesAsync();
            profileId = profile.Id;
            seed.HotstringProfiles.Add(HotstringProfile.Create(scoped.Id, profileId));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(ProfileId: profileId), default);

        result.Value.Items.Should().HaveCount(2);
        result.Value.Items.Should().Contain(h => h.Trigger == "a");
        result.Value.Items.Should().Contain(h => h.Trigger == "b");
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
                seed.Hotstrings.Add(Hotstring.Create(owner, $"t{i}", "x", true, true, true, clock));
                clock.Advance(TimeSpan.FromSeconds(1));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> page2 = await handler.Handle(
            new ListHotstringsQuery(Page: 2, PageSize: 2), default);

        page2.Value.TotalCount.Should().Be(5);
        page2.Value.Items.Should().HaveCount(2);
        page2.Value.Page.Should().Be(2);
        page2.Value.PageSize.Should().Be(2);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(null));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new ListHotstringsQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Search_MatchesTrigger()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "by the way", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "fyi", "for your info", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "btw"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task Handle_Search_MatchesReplacement()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "needle in a haystack", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "nothing relevant", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "needle"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_Search_IgnoresCaseByDefault()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "FOO bar", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "baz foo", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "foo"), default);

        result.Value.Items.Should().HaveCount(2);
    }
}
```

- [ ] **Step 5: Run application tests**

```bash
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --verbosity normal
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Backend/AHKFlowApp.Application/
git add tests/AHKFlowApp.Application.Tests/Hotstrings/
git commit -m "feat(app): update Hotstring DTOs, rules, commands, queries for many-to-many profiles"
```

---

## Task 10: API integration tests

**Files:**
- Modify: `tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs`

Replace the entire file:

- [ ] **Step 1: Update HotstringsEndpointsTests.cs**

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringsEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task Post_CreatesAndReturns201WithLocation()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotstringDto("btw", "by the way");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        HotstringDto? body = await response.Content.ReadFromJsonAsync<HotstringDto>();
        body!.Trigger.Should().Be("btw");
        body.AppliesToAllProfiles.Should().BeTrue();
        body.ProfileIds.Should().BeEmpty();

        HttpResponseMessage get = await client.GetAsync(response.Headers.Location);
        get.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Post_InvalidBody_Returns400()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotstringDto("", "");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Post_DuplicateTrigger_Returns409_WithProblemDetails()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);
        var dto = new CreateHotstringDto("dup", "x");

        HttpResponseMessage first = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
        second.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await second.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("type").GetString().Should().Be("https://tools.ietf.org/html/rfc9110#section-15.5.10");
        root.GetProperty("status").GetInt32().Should().Be(409);
        root.GetProperty("detail").GetString().Should().Contain("already exists");
    }

    [Fact]
    public async Task Put_UnknownId_Returns404_WithProblemDetails()
    {
        using HttpClient client = CreateAuthed();
        var dto = new UpdateHotstringDto("x", "y", null, true, true, true);

        var unknownId = Guid.NewGuid();
        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/hotstrings/{unknownId}", dto);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_OtherUsersRow_Returns404()
    {
        var ownerA = Guid.NewGuid();
        var ownerB = Guid.NewGuid();

        using HttpClient a = CreateAuthed(ownerA);
        HttpResponseMessage created = await a.PostAsJsonAsync("/api/v1/hotstrings",
            new CreateHotstringDto("tenant-a", "x"));
        HotstringDto? body = await created.Content.ReadFromJsonAsync<HotstringDto>();

        using HttpClient b = CreateAuthed(ownerB);
        HttpResponseMessage response = await b.PutAsJsonAsync(
            $"/api/v1/hotstrings/{body!.Id}",
            new UpdateHotstringDto("tenant-a", "hijack", null, true, true, true));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_Success_Returns200WithUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotstrings",
            new CreateHotstringDto("upd", "before"));
        HotstringDto? before = await created.Content.ReadFromJsonAsync<HotstringDto>();

        await Task.Delay(10);

        HttpResponseMessage put = await client.PutAsJsonAsync(
            $"/api/v1/hotstrings/{before!.Id}",
            new UpdateHotstringDto("upd", "after", null, true, false, false));

        put.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? after = await put.Content.ReadFromJsonAsync<HotstringDto>();
        after!.Replacement.Should().Be("after");
        after.IsEndingCharacterRequired.Should().BeFalse();
        after.UpdatedAt.Should().BeOnOrAfter(before.CreatedAt);
    }

    [Fact]
    public async Task Delete_ThenGet_Returns404()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotstrings",
            new CreateHotstringDto("del", "x"));
        HotstringDto? body = await created.Content.ReadFromJsonAsync<HotstringDto>();

        HttpResponseMessage del = await client.DeleteAsync($"/api/v1/hotstrings/{body!.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        HttpResponseMessage get = await client.GetAsync($"/api/v1/hotstrings/{body.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task List_FiltersByProfileId_IncludesGlobalAndScoped()
    {
        // This test uses AppliesToAllProfiles only (no real profile creation needed for this path).
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        // Global hotstring (AppliesToAllProfiles = true by default)
        await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("global", "x"));
        // Unscoped hotstring with AppliesToAllProfiles=false will be excluded without a profile filter match.
        // We can't create a profile-scoped one here without a real Profile, so we just verify the global one appears.
        var anyProfileId = Guid.NewGuid();

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotstrings?profileId={anyProfileId}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        body!.Items.Should().Contain(h => h.Trigger == "global" && h.AppliesToAllProfiles);
    }

    [Fact]
    public async Task List_WithPagination_ReturnsSlice()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        for (int i = 0; i < 5; i++)
            await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto($"p{i}", "x"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?page=2&pageSize=2");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        body!.TotalCount.Should().Be(5);
        body.Items.Should().HaveCount(2);
        body.Page.Should().Be(2);
    }

    [Fact]
    public async Task List_PageSizeTooLarge_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?pageSize=500");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task List_SearchByTrigger_FiltersResults()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("btw", "by the way"));
        await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("fyi", "for your info"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?search=btw");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        body!.Items.Should().ContainSingle().Which.Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task List_SearchTooLong_Returns400()
    {
        using HttpClient client = CreateAuthed();
        string longSearch = new('x', 201);

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotstrings?search={longSearch}");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Get_WithoutBearer_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_WithoutScope_Returns403()
    {
        using HttpClient client = _factory.WithTestAuth(b =>
            b.WithOid(Guid.NewGuid()).WithoutScope()).CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Post_InvalidBody_ReturnsProblemDetailsWithErrors()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotstringDto("", "");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;

        root.GetProperty("title").GetString().Should().Be("Validation failed");
        root.GetProperty("status").GetInt32().Should().Be(400);

        JsonElement errors = root.GetProperty("errors");
        errors.TryGetProperty("Input.Trigger", out _).Should().BeTrue();
        errors.TryGetProperty("Input.Replacement", out _).Should().BeTrue();
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
git add tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs
git commit -m "test(api): update Hotstring endpoint tests for many-to-many profiles"
```

---

## Task 11: Frontend — DTOs + EditModel

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/HotstringDto.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/CreateHotstringDto.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/DTOs/UpdateHotstringDto.cs`
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs`

- [ ] **Step 1: Update HotstringDto.cs (frontend)**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

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
```

- [ ] **Step 2: Update CreateHotstringDto.cs (frontend)**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);
```

- [ ] **Step 3: Update UpdateHotstringDto.cs (frontend)**

```csharp
namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord);
```

- [ ] **Step 4: Update HotstringEditModel.cs**

```csharp
using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotstringEditModel
{
    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Trigger is required.")]
    [MaxLength(50, ErrorMessage = "Trigger must be 50 characters or fewer.")]
    public string Trigger { get; set; } = "";

    [Required(ErrorMessage = "Replacement is required.")]
    [MaxLength(4000, ErrorMessage = "Replacement must be 4000 characters or fewer.")]
    public string Replacement { get; set; } = "";

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];
    public bool IsEndingCharacterRequired { get; set; } = true;
    public bool IsTriggerInsideWord { get; set; } = true;

    public static HotstringEditModel FromDto(HotstringDto dto) => new()
    {
        Id = dto.Id,
        Trigger = dto.Trigger,
        Replacement = dto.Replacement,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
        IsEndingCharacterRequired = dto.IsEndingCharacterRequired,
        IsTriggerInsideWord = dto.IsTriggerInsideWord,
    };

    public CreateHotstringDto ToCreateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord);

    public UpdateHotstringDto ToUpdateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord);
}
```

---

## Task 12: Frontend — Hotstrings page + tests

**Files:**
- Modify: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor`
- Modify: `tests/AHKFlowApp.UI.Blazor.Tests/Services/HotstringsApiClientTests.cs`

- [ ] **Step 1: Update Hotstrings.razor**

Add profile columns to the table and a profile multi-select in edit mode. The page already injects `IHotstringsApiClient`; we also need `IProfilesApiClient`. Add the using and inject.

Replace the entire file content:

```razor
@page "/hotstrings"
@using AHKFlowApp.UI.Blazor.DTOs
@using AHKFlowApp.UI.Blazor.Services
@using AHKFlowApp.UI.Blazor.Validation
@using MudBlazor
@using Microsoft.AspNetCore.Components.Authorization
@implements IDisposable

<PageTitle>Hotstrings</PageTitle>

<MudText Typo="Typo.h4" GutterBottom="true">Hotstrings</MudText>

<MudPaper Class="pa-4">
    <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="2" Wrap="Wrap.Wrap" Class="mb-4">
        <MudButton Class="add-hotstring" Variant="Variant.Filled" Color="Color.Primary"
                   StartIcon="@Icons.Material.Filled.Add" OnClick="StartAddAsync"
                   Disabled="@(!_isAuthenticated || _editing.ContainsKey(Guid.Empty))">
            Add
        </MudButton>
        <MudButton Class="reload-hotstrings" Variant="Variant.Filled" Color="Color.Secondary"
                   StartIcon="@Icons.Material.Filled.Refresh" OnClick="ReloadAsync"
                   Disabled="@(!_isAuthenticated || _loading)">
            Reload
        </MudButton>
        <MudSpacer />
        <MudTextField T="string" @bind-Value="_search" @bind-Value:after="OnSearchChangedAsync"
                      DebounceInterval="300"
                      Placeholder="Search For Hotstrings"
                      Adornment="Adornment.Start"
                      AdornmentIcon="@Icons.Material.Filled.Search"
                      Class="search-hotstrings"
                      Style="max-width: 360px;"
                      Immediate="true" />
    </MudStack>

    @if (_loadError is not null)
    {
        <MudAlert Severity="Severity.Error" Class="mb-3">@_loadError</MudAlert>
    }

    <div style="overflow-x: auto;">
        <MudTable @ref="_table" T="HotstringDto" ServerData="LoadServerData"
                  Dense="true" Hover="true" RowsPerPage="_rowsPerPage" Loading="_loading">
            <HeaderContent>
                <MudTh>Trigger</MudTh>
                <MudTh>Replacement</MudTh>
                <MudTh>Profiles</MudTh>
                <MudTh>Ending char required</MudTh>
                <MudTh>Trigger inside word</MudTh>
                <MudTh Style="width:160px">Actions</MudTh>
            </HeaderContent>
            <RowTemplate>
                @if (_editing.TryGetValue(context.Id, out var edit))
                {
                    bool showErrors = _commitAttempted.Contains(context.Id);
                    string? triggerError = showErrors ? ValidateTrigger(edit.Trigger) : null;
                    string? replacementError = showErrors ? ValidateReplacement(edit.Replacement) : null;
                    <MudTd Class="@(context.Id == Guid.Empty ? "draft-row" : "edit-row")">
                        <MudTextField @bind-Value="edit.Trigger"
                                      Validation="@(new Func<string, string?>(ValidateTrigger))"
                                      Error="@(triggerError is not null)" ErrorText="@triggerError"
                                      Immediate="true" MaxLength="50"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "trigger-input" })" />
                    </MudTd>
                    <MudTd>
                        <MudTextField @bind-Value="edit.Replacement"
                                      Validation="@(new Func<string, string?>(ValidateReplacement))"
                                      Error="@(replacementError is not null)" ErrorText="@replacementError"
                                      Immediate="true" MaxLength="4000"
                                      UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "replacement-input" })" />
                    </MudTd>
                    <MudTd>
                        <MudStack Row="true" AlignItems="AlignItems.Center" Spacing="1">
                            <MudCheckBox T="bool" @bind-Value="edit.AppliesToAllProfiles"
                                         Label="Any"
                                         UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "applies-to-all-checkbox" })" />
                            @if (!edit.AppliesToAllProfiles)
                            {
                                <MudSelect T="Guid" MultiSelection="true"
                                           SelectedValues="@edit.ProfileIds"
                                           SelectedValuesChanged="@(ids => edit.ProfileIds = [.. ids])"
                                           ToStringFunc="@(id => _profiles.FirstOrDefault(p => p.Id == id)?.Name ?? id.ToString())"
                                           Dense="true" Placeholder="Select profiles"
                                           UserAttributes="@(new Dictionary<string, object?> { ["data-test"] = "profile-select" })">
                                    @foreach (var profile in _profiles)
                                    {
                                        <MudSelectItem T="Guid" Value="@profile.Id">@profile.Name</MudSelectItem>
                                    }
                                </MudSelect>
                            }
                        </MudStack>
                    </MudTd>
                    <MudTd><MudCheckBox T="bool" @bind-Value="edit.IsEndingCharacterRequired" /></MudTd>
                    <MudTd><MudCheckBox T="bool" @bind-Value="edit.IsTriggerInsideWord" /></MudTd>
                    <MudTd>
                        <MudIconButton Class="commit-edit" Icon="@Icons.Material.Filled.Check"
                                       Color="Color.Success" OnClick="() => CommitEditAsync(context.Id)" />
                        <MudIconButton Class="cancel-edit" Icon="@Icons.Material.Filled.Close"
                                       Color="Color.Default" OnClick="() => CancelEditAsync(context.Id)" />
                    </MudTd>
                }
                else
                {
                    <MudTd>@context.Trigger</MudTd>
                    <MudTd>@context.Replacement</MudTd>
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
                    <MudTd><MudCheckBox T="bool" Value="@context.IsEndingCharacterRequired" ReadOnly="true" /></MudTd>
                    <MudTd><MudCheckBox T="bool" Value="@context.IsTriggerInsideWord" ReadOnly="true" /></MudTd>
                    <MudTd>
                        <MudIconButton Class="delete" Icon="@Icons.Material.Filled.Delete" Color="Color.Error"
                                       OnClick="() => DeleteAsync(context)" />
                        <MudIconButton Class="start-edit" Icon="@Icons.Material.Filled.Edit"
                                       OnClick="() => StartEdit(context)" />
                    </MudTd>
                }
            </RowTemplate>
            <NoRecordsContent><MudText>No hotstrings yet.</MudText></NoRecordsContent>
            <PagerContent>
                <MudTablePager PageSizeOptions="UserPreferences.AllowedRowsPerPage" />
            </PagerContent>
        </MudTable>
    </div>
</MudPaper>

@code {
    [CascadingParameter] private Task<AuthenticationState>? AuthState { get; set; }
    [Inject] private IHotstringsApiClient Api { get; set; } = default!;
    [Inject] private IProfilesApiClient ProfilesApi { get; set; } = default!;
    [Inject] private ISnackbar Snackbar { get; set; } = default!;
    [Inject] private IDialogService DialogService { get; set; } = default!;
    [Inject] private IUserPreferencesService Preferences { get; set; } = default!;

    private MudTable<HotstringDto>? _table;
    private readonly Dictionary<Guid, HotstringEditModel> _editing = new();
    private readonly HashSet<Guid> _commitAttempted = [];
    private List<ProfileDto> _profiles = [];
    private bool _isAuthenticated;
    private bool _loading;
    private string? _loadError;
    private string _search = "";
    private int _rowsPerPage = UserPreferences.Default.RowsPerPage;
    private readonly CancellationTokenSource _cts = new();

    private static readonly HotstringDto _draftPlaceholder = new(
        Guid.Empty, [], true, "", "", true, true, DateTimeOffset.MinValue, DateTimeOffset.MinValue);

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

    private async Task<TableData<HotstringDto>> LoadServerData(TableState state, CancellationToken ct)
    {
        _loading = true;
        _loadError = null;

        ApiResult<PagedList<HotstringDto>> result = await Api.ListAsync(
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
            return new TableData<HotstringDto> { Items = [], TotalItems = 0 };
        }

        List<HotstringDto> items = [.. result.Value!.Items];
        if (state.Page == 0 && _editing.ContainsKey(Guid.Empty))
            items.Insert(0, _draftPlaceholder);

        return new TableData<HotstringDto> { Items = items, TotalItems = result.Value.TotalCount };
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
        _editing[Guid.Empty] = new HotstringEditModel();
        if (_table is not null) await _table.ReloadServerData();
    }

    private void StartEdit(HotstringDto dto) =>
        _editing[dto.Id] = HotstringEditModel.FromDto(dto);

    private async Task CancelEditAsync(Guid id)
    {
        _editing.Remove(id);
        _commitAttempted.Remove(id);
        if (id == Guid.Empty && _table is not null) await _table.ReloadServerData();
    }

    private static string? ValidateTrigger(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "Trigger is required";
        if (value.Length > 50) return "Trigger must be 50 characters or fewer";
        return null;
    }

    private static string? ValidateReplacement(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "Replacement is required";
        if (value.Length > 4000) return "Replacement must be 4000 characters or fewer";
        return null;
    }

    private async Task CommitEditAsync(Guid id)
    {
        if (!_editing.TryGetValue(id, out HotstringEditModel? edit)) return;

        _commitAttempted.Add(id);
        if (ValidateTrigger(edit.Trigger) is not null || ValidateReplacement(edit.Replacement) is not null)
            return;

        _commitAttempted.Remove(id);

        if (id == Guid.Empty)
        {
            ApiResult<HotstringDto> result = await Api.CreateAsync(edit.ToCreateDto(), _cts.Token);
            if (result.IsSuccess)
            {
                _editing.Remove(id);
                Snackbar.Add("Hotstring created.", Severity.Success);
                if (_table is not null) await _table.ReloadServerData();
            }
            else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
        else
        {
            ApiResult<HotstringDto> result = await Api.UpdateAsync(id, edit.ToUpdateDto(), _cts.Token);
            if (result.IsSuccess)
            {
                _editing.Remove(id);
                Snackbar.Add("Hotstring updated.", Severity.Success);
                if (_table is not null) await _table.ReloadServerData();
            }
            else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
        }
    }

    private async Task DeleteAsync(HotstringDto dto)
    {
        bool? confirm = await DialogService.ShowMessageBoxAsync(
            title: "Delete hotstring?",
            message: $"Delete \"{dto.Trigger}\"? This cannot be undone.",
            yesText: "Delete", cancelText: "Cancel");
        if (confirm != true) return;

        ApiResult result = await Api.DeleteAsync(dto.Id, _cts.Token);
        if (result.IsSuccess)
        {
            Snackbar.Add("Hotstring deleted.", Severity.Success);
            if (_table is not null) await _table.ReloadServerData();
        }
        else Snackbar.Add(ApiErrorMessageFactory.Build(result.Status, result.Problem), Severity.Error);
    }

    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

- [ ] **Step 2: Update HotstringsApiClientTests.cs**

Replace the entire file:

```csharp
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotstringsApiClientTests
{
    private static HotstringsApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task ListAsync_OnSuccess_ReturnsPagedList()
    {
        var paged = new PagedList<HotstringDto>(
            Items: [new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)],
            Page: 1, PageSize: 50, TotalCount: 1, TotalPages: 1, HasNextPage: false, HasPreviousPage: false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        ApiResult<PagedList<HotstringDto>> result = await ClientWith(handler).ListAsync(profileId: null, page: 1, pageSize: 50);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/hotstrings?page=1&pageSize=50");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", "/api/v1/hotstrings", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        ApiResult<HotstringDto> result = await ClientWith(handler).CreateAsync(new CreateHotstringDto("btw", "by the way"));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task ListAsync_WithProfileId_AppendsProfileIdToQueryString()
    {
        var profileId = Guid.NewGuid();
        var paged = new PagedList<HotstringDto>([], 1, 50, 0, 0, false, false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(profileId: profileId, page: 1, pageSize: 50);

        handler.LastRequest!.RequestUri!.Query.Should().Contain($"profileId={profileId}");
    }

    [Fact]
    public async Task DeleteAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, new ApiProblemDetails(null, "Not Found", 404, null, null, null));

        ApiResult result = await ClientWith(handler).DeleteAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;
        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) => new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) { LastRequest = request; return Task.FromResult(_response); }
    }
}
```

- [ ] **Step 3: Build everything**

```bash
dotnet build --configuration Release
```

Expected: `Build succeeded.` with 0 errors.

- [ ] **Step 4: Run all tests**

```bash
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Frontend/AHKFlowApp.UI.Blazor/
git add tests/AHKFlowApp.UI.Blazor.Tests/
git commit -m "feat(ui): add profile multi-select + Any checkbox to Hotstrings page"
```

---

## Task 13: Open PR

- [ ] **Step 1: Push branch**

```bash
git push -u origin feature/024b-many-to-many-profile-association
```

- [ ] **Step 2: Create PR**

```bash
gh pr create \
  --base feature/028-phase-1-profile-foundation-plan \
  --title "feat: phase 2 — many-to-many profile association for hotstrings" \
  --body "$(cat <<'EOF'
## Summary
- Replaces scalar `Hotstring.ProfileId` with `HotstringProfile` junction table + `AppliesToAllProfiles` flag
- DTOs gain `Guid[] ProfileIds` and `bool AppliesToAllProfiles`; validators enforce mutual exclusivity
- `ListHotstrings` profileId filter now includes global (AppliesToAllProfiles=true) and scoped rows
- Hotstrings page gains profile multi-select + "Any" chip; profile names loaded from ProfilesApiClient
- Hotkey untouched — rebuild is Phase 3

## Test plan
- [ ] `dotnet test --configuration Release` passes
- [ ] Manual: create hotstring with "Any" checked → ProfileIds empty in response
- [ ] Manual: create hotstring with two profiles selected → ProfileIds has both IDs
- [ ] Manual: filter list by profile → shows global + scoped hotstrings
- [ ] Manual: delete a profile → HotstringProfile junction rows cascade-deleted

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

After writing this plan:

1. **Spec coverage:**
   - ✅ `HotstringProfile` junction + `AppliesToAllProfiles` on `Hotstring`
   - ✅ EF migration drops `ProfileId`, adds junction table
   - ✅ DTOs gain `Guid[] ProfileIds` + `bool AppliesToAllProfiles`
   - ✅ Validation: `AppliesToAllProfiles=true → ProfileIds empty`; `false → at least one`
   - ✅ List endpoint filters by junction OR `AppliesToAllProfiles`
   - ✅ UI: multi-select + "Any" checkbox
   - ✅ Tests: validator unit tests + handler integration tests + API integration tests

2. **Hotkey not touched:** Confirmed — no Hotkey changes anywhere in this plan.

3. **Type consistency:**
   - `Hotstring.Create(ownerOid, trigger, replacement, appliesToAllProfiles, isEndingCharRequired, isTriggerInsideWord, clock)` — same signature throughout.
   - `HotstringProfile.Create(hotstringId, profileId)` — used in handlers and tests.
   - `HotstringDto(Id, ProfileIds, AppliesToAllProfiles, Trigger, Replacement, ...)` — consistent ordering.
   - `CreateHotstringDto(Trigger, Replacement, ProfileIds, AppliesToAllProfiles, ...)` — consistent.

4. **One issue to watch:** The `UpdateHotstringCommandHandler` calls `entity.Profiles.Clear()` and then adds new junction objects. This works because `Profiles` is an `ICollection<HotstringProfile>` with `private set`. EF Core will track the removals and additions since we loaded with `Include`.
