using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

/// <summary>
/// Goes straight at <see cref="AppDbContext"/>, with no handler in the path. Create rejects a
/// duplicate before it reaches SQL, so a handler-level test still passes when the unique index is
/// wrong. Restore and revert have no such pre-check, so the index is their only guard.
/// </summary>
[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class HotkeyPersistenceTests(SqlContainerFixture sqlFixture)
{
    private DbContextOptions<AppDbContext> CreateOptions()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotkeyPersistenceTests",
        };

        return new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;
    }

    [Fact]
    public async Task SaveAndReload_ContextFields_RoundTrip()
    {
        DbContextOptions<AppDbContext> options = CreateOptions();

        Hotkey entity = new HotkeyBuilder()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext write = new(options))
        {
            await write.Database.MigrateAsync();
            write.Hotkeys.Add(entity);
            await write.SaveChangesAsync();
        }

        await using AppDbContext read = new(options);
        Hotkey reloaded = await read.Hotkeys.SingleAsync(h => h.Id == entity.Id);

        reloaded.ContextMatchType.Should().Be(WindowMatchType.Executable);
        reloaded.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public async Task Save_TwoGlobalRowsSameCombination_ThrowsDuplicateKey()
    {
        DbContextOptions<AppDbContext> options = CreateOptions();

        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder().WithOwner(owner).WithKey("e").WithCtrl().WithShift().Build();
        Hotkey second = new HotkeyBuilder().WithOwner(owner).WithKey("e").WithCtrl().WithShift().Build();

        await using AppDbContext write = new(options);
        await write.Database.MigrateAsync();
        write.Hotkeys.Add(first);
        await write.SaveChangesAsync();

        write.Hotkeys.Add(second);
        Func<Task> act = async () => await write.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }

    [Fact]
    public async Task Save_SameCombinationDifferentContext_Succeeds()
    {
        DbContextOptions<AppDbContext> options = CreateOptions();

        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder()
            .WithOwner(owner).WithKey("e").WithCtrl().WithShift()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();
        Hotkey second = new HotkeyBuilder()
            .WithOwner(owner).WithKey("e").WithCtrl().WithShift()
            .WithContext(WindowMatchType.Executable, "code.exe")
            .Build();

        await using AppDbContext write = new(options);
        await write.Database.MigrateAsync();
        write.Hotkeys.AddRange(first, second);
        Func<Task> act = async () => await write.SaveChangesAsync();

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task Save_SameCombinationSameContext_ThrowsDuplicateKey()
    {
        DbContextOptions<AppDbContext> options = CreateOptions();

        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder()
            .WithOwner(owner).WithKey("e").WithCtrl().WithShift()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();
        Hotkey second = new HotkeyBuilder()
            .WithOwner(owner).WithKey("e").WithCtrl().WithShift()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using AppDbContext write = new(options);
        await write.Database.MigrateAsync();
        write.Hotkeys.Add(first);
        await write.SaveChangesAsync();

        write.Hotkeys.Add(second);
        Func<Task> act = async () => await write.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }
}
