using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class PreviewHotstringImportCommandHandlerTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    private PreviewHotstringImportCommandHandler Handler(AppDbContext db, Guid owner) =>
        new(db, CurrentUserHelper.For(owner));

    [Fact]
    public async Task Handle_ExistingTrigger_MarkedDuplicate_CaseInsensitive()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "BTW", "existing", null, true, true, false, _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand("::btw::by the way"), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.DuplicateCount.Should().Be(1);
        result.Value.Rows[0].Status.Should().Be(HotstringImportRowStatus.Duplicate);
    }

    [Fact]
    public async Task Handle_InFileRepeat_FirstReadyRestDuplicate()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand("::btw::first\n::btw::second"), default);

        result.Value.ReadyCount.Should().Be(1);
        result.Value.DuplicateCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_CountsAllStatuses()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        string script = string.Join('\n',
            "::ok::fine",          // Ready
            ":C:warn::flagged",    // Warning
            "::bad::");            // Invalid (empty replacement)

        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand(script), default);

        result.Value.ReadyCount.Should().Be(1);
        result.Value.WarningCount.Should().Be(1);
        result.Value.InvalidCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_OverRowCap_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();

        string script = string.Join('\n',
            Enumerable.Range(0, 1001).Select(i => $"::t{i}::r{i}"));

        Result<HotstringImportPreviewDto> result = await Handler(db, owner).ExecuteAsync(
            new PreviewHotstringImportCommand(script), default);

        result.Status.Should().Be(ResultStatus.Invalid);
    }

    [Fact]
    public async Task Handle_NoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new PreviewHotstringImportCommandHandler(db, CurrentUserHelper.For(null));

        Result<HotstringImportPreviewDto> result = await handler.ExecuteAsync(
            new PreviewHotstringImportCommand("::btw::x"), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
