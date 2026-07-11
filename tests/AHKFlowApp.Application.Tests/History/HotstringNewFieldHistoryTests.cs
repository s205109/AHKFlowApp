using System.Text.Json;
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

    [Fact]
    public async Task RevertHotstring_RestoresDateTimeFields()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("dt1").WithReplacement("")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy-MM-dd")
            .WithDateOffset(1, DateOffsetUnit.Days)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Update switches the hotstring to Text kind — the before-image snapshot must carry the date fields.
        await using (AppDbContext db = fx.CreateContext())
        {
            UpdateHotstringCommandHandler update = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));
            Result<HotstringDto> updated = await update.ExecuteAsync(
                new UpdateHotstringCommand(entity.Id,
                    new UpdateHotstringDto("dt1", "x", null, true, true, true, null)), default);
            updated.IsSuccess.Should().BeTrue();
            updated.Value.Kind.Should().Be(HotstringKind.Text);
        }

        await using AppDbContext revertDb = fx.CreateContext();
        RevertHotstringCommandHandler revert = new(
            revertDb, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(revertDb, TimeProvider.System));
        Result<HotstringDto> result = await revert.ExecuteAsync(
            new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Kind.Should().Be(HotstringKind.DateTime);
        result.Value.DateTimeFormat.Should().Be("yyyy-MM-dd");
        result.Value.DateOffsetAmount.Should().Be(1);
        result.Value.DateOffsetUnit.Should().Be(DateOffsetUnit.Days);
    }

    [Fact]
    public async Task RestoreHotstring_AfterDelete_RehydratesDateTimeFields()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("dt2").WithReplacement("")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("HH:mm")
            .WithDateOffset(-2, DateOffsetUnit.Hours)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Delete via the real handler so the tombstone snapshot is written the production way.
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
        result.Value.Kind.Should().Be(HotstringKind.DateTime);
        result.Value.DateTimeFormat.Should().Be("HH:mm");
        result.Value.DateOffsetAmount.Should().Be(-2);
        result.Value.DateOffsetUnit.Should().Be(DateOffsetUnit.Hours);
    }

    [Fact]
    public async Task RevertHotstring_RestoresMacroKindAndTokenReplacement()
    {
        var owner = Guid.NewGuid();
        const string macroReplacement = "Dear {{cursor}}Alex";
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("macro1").WithReplacement(macroReplacement)
            .WithKind(HotstringKind.Macro)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Update switches the hotstring to Text kind with a plain replacement — the before-image
        // snapshot must carry the original Macro kind and token-bearing replacement intact.
        await using (AppDbContext db = fx.CreateContext())
        {
            UpdateHotstringCommandHandler update = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));
            Result<HotstringDto> updated = await update.ExecuteAsync(
                new UpdateHotstringCommand(entity.Id,
                    new UpdateHotstringDto("macro1", "plain text", null, true, true, true, null)), default);
            updated.IsSuccess.Should().BeTrue();
            updated.Value.Kind.Should().Be(HotstringKind.Text);
        }

        await using AppDbContext revertDb = fx.CreateContext();
        RevertHotstringCommandHandler revert = new(
            revertDb, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(revertDb, TimeProvider.System));
        Result<HotstringDto> result = await revert.ExecuteAsync(
            new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Kind.Should().Be(HotstringKind.Macro);
        result.Value.Replacement.Should().Be(macroReplacement);
    }

    [Fact]
    public async Task RecordHotstringAsync_ContextFields_CapturedInSnapshot()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("ctxhist").WithReplacement("x")
            .WithContext(WindowMatchType.TitleContains, "- Visual Studio")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);
        EntityHistory entry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(entry.SnapshotJson);
        snapshot!.ContextMatchType.Should().Be(WindowMatchType.TitleContains);
        snapshot.ContextValue.Should().Be("- Visual Studio");
    }

    [Fact]
    public async Task ExecuteAsync_RevertToContextedVersion_RestoresContextFields()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("ctxrevert").WithReplacement("x")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Update clears the context — the before-image snapshot must carry it.
        await using (AppDbContext db = fx.CreateContext())
        {
            UpdateHotstringCommandHandler update = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));
            Result<HotstringDto> updated = await update.ExecuteAsync(
                new UpdateHotstringCommand(entity.Id,
                    new UpdateHotstringDto("ctxrevert", "x", null, true, true, true, null)), default);
            updated.IsSuccess.Should().BeTrue();
            updated.Value.ContextMatchType.Should().BeNull();
        }

        await using AppDbContext revertDb = fx.CreateContext();
        RevertHotstringCommandHandler revert = new(
            revertDb, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(revertDb, TimeProvider.System));
        Result<HotstringDto> result = await revert.ExecuteAsync(
            new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ContextMatchType.Should().Be(WindowMatchType.Executable);
        result.Value.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public async Task ExecuteAsync_RestoreContextedHotstring_RestoresContextFields()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("ctxrestore").WithReplacement("x")
            .WithContext(WindowMatchType.WindowClass, "Notepad")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Delete via the real handler so the tombstone snapshot is written the production way.
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
        result.Value.ContextMatchType.Should().Be(WindowMatchType.WindowClass);
        result.Value.ContextValue.Should().Be("Notepad");
    }
}
