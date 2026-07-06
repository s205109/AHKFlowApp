using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class ImportHotstringsCommandHandlerTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    private ImportHotstringsCommandHandler Handler(AppDbContext db, Guid owner) =>
        new(db, CurrentUserHelper.For(owner), _clock);

    [Fact]
    public async Task Handle_ReadyAndWarningRows_Inserted_InvalidSkipped()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        string script = string.Join('\n',
            "::ok::fine",         // Ready
            ":C:warn::flagged",   // Warning (imports)
            "::bad::");           // Invalid (skipped)

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(script)), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ImportedCount.Should().Be(2);
        result.Value.WarningCount.Should().Be(1);

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner)).Should().Be(2);
    }

    [Fact]
    public async Task Handle_SpecificProfiles_LinksJunctionRows()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).WithName("Work").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(
                "::btw::by the way", AppliesToAllProfiles: false, ProfileIds: [profile.Id])), default);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.HotstringProfiles.CountAsync(hp => hp.ProfileId == profile.Id)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_UnknownProfile_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(
                "::btw::x", AppliesToAllProfiles: false, ProfileIds: [Guid.NewGuid()])), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }

    [Fact]
    public async Task Handle_InFileRepeat_ImportsFirstReportsSecondDuplicate()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto("::btw::first\n::btw::second")), default);

        result.Value.ImportedCount.Should().Be(1);
        result.Value.Rows.Should().Contain(r => r.Status == HotstringImportRowStatus.Duplicate);

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "btw")).Should().Be(1);
    }

    // Existing-trigger collision + the concurrent-create race share the detach/retry net:
    // pre-seeding an overlapping trigger forces the duplicate-key exception deterministically.
    [Fact]
    public async Task Handle_ExistingTrigger_DetachesReFiltersAndImportsTheRest()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "pre-existing", null, true, true, false, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto("::btw::dup\n::new::fresh")), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ImportedCount.Should().Be(1);
        result.Value.Rows.Single(r => r.Trigger == "btw").Status.Should().Be(HotstringImportRowStatus.Duplicate);
        result.Value.Rows.Single(r => r.Trigger == "new").Status.Should().Be(HotstringImportRowStatus.Ready);

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "btw")).Should().Be(1);
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "new")).Should().Be(1);
    }

    [Fact]
    public async Task Handle_FullyDuplicateFile_ImportsNothing_ReturnsSuccess()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "x", null, true, true, false, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto("::btw::again")), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ImportedCount.Should().Be(0);
    }

    [Fact]
    public async Task Handle_OverRowCap_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        string script = string.Join('\n', Enumerable.Range(0, 1001).Select(i => $"::t{i}::r{i}"));

        Result<HotstringImportResultDto> result = await Handler(db, owner).ExecuteAsync(
            new ImportHotstringsCommand(new ImportHotstringsRequestDto(script)), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }
}
