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

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class HotstringPersistenceTests(SqlContainerFixture sqlFixture)
{
    [Fact]
    public async Task SaveAndReload_KindAndOptionFlags_RoundTrip()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        Hotstring entity = new HotstringBuilder()
            .WithCaseSensitive(true)
            .WithOmitEndingCharacter(true)
            .Build();

        await using (AppDbContext write = new(options))
        {
            await write.Database.MigrateAsync();
            write.Hotstrings.Add(entity);
            await write.SaveChangesAsync();
        }

        await using AppDbContext read = new(options);
        Hotstring reloaded = await read.Hotstrings.SingleAsync(h => h.Id == entity.Id);

        reloaded.Kind.Should().Be(HotstringKind.Text);
        reloaded.IsCaseSensitive.Should().BeTrue();
        reloaded.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public async Task SaveAndReload_DateTimeFields_RoundTrip()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        Hotstring entityWithDateTime = new HotstringBuilder()
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy-MM-dd")
            .WithDateOffset(3, DateOffsetUnit.Days)
            .Build();

        Hotstring entityWithoutDateTime = new HotstringBuilder()
            .WithKind(HotstringKind.Text)
            .Build();

        await using (AppDbContext write = new(options))
        {
            await write.Database.MigrateAsync();
            write.Hotstrings.AddRange(entityWithDateTime, entityWithoutDateTime);
            await write.SaveChangesAsync();
        }

        await using AppDbContext read = new(options);
        Hotstring reloadedWithDateTime = await read.Hotstrings.SingleAsync(h => h.Id == entityWithDateTime.Id);
        Hotstring reloadedWithoutDateTime = await read.Hotstrings.SingleAsync(h => h.Id == entityWithoutDateTime.Id);

        reloadedWithDateTime.DateTimeFormat.Should().Be("yyyy-MM-dd");
        reloadedWithDateTime.DateOffsetAmount.Should().Be(3);
        reloadedWithDateTime.DateOffsetUnit.Should().Be(DateOffsetUnit.Days);

        reloadedWithoutDateTime.DateTimeFormat.Should().BeNull();
        reloadedWithoutDateTime.DateOffsetAmount.Should().BeNull();
        reloadedWithoutDateTime.DateOffsetUnit.Should().BeNull();
    }

    [Fact]
    public async Task SaveAndReload_ContextFields_RoundTrip()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        Hotstring entity = new HotstringBuilder()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext write = new(options))
        {
            await write.Database.MigrateAsync();
            write.Hotstrings.Add(entity);
            await write.SaveChangesAsync();
        }

        await using AppDbContext read = new(options);
        Hotstring reloaded = await read.Hotstrings.SingleAsync(h => h.Id == entity.Id);

        reloaded.ContextMatchType.Should().Be(WindowMatchType.Executable);
        reloaded.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public async Task Save_SameTriggerDifferentContext_Succeeds()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        var owner = Guid.NewGuid();
        Hotstring first = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("btw")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();
        Hotstring second = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("btw")
            .WithContext(WindowMatchType.Executable, "code.exe")
            .Build();

        await using AppDbContext write = new(options);
        await write.Database.MigrateAsync();
        write.Hotstrings.AddRange(first, second);
        Func<Task> act = async () => await write.SaveChangesAsync();

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task Save_SameTriggerSameContext_ThrowsDuplicateKey()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        var owner = Guid.NewGuid();
        Hotstring first = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("btw")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();
        Hotstring second = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("btw")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using AppDbContext write = new(options);
        await write.Database.MigrateAsync();
        write.Hotstrings.Add(first);
        await write.SaveChangesAsync();

        write.Hotstrings.Add(second);
        Func<Task> act = async () => await write.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }

    [Fact]
    public async Task Save_TwoGlobalRowsSameTrigger_ThrowsDuplicateKey()
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString)
        {
            InitialCatalog = "HotstringPersistenceTests",
        };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        var owner = Guid.NewGuid();
        Hotstring first = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("btw")
            .Build();
        Hotstring second = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("btw")
            .Build();

        await using AppDbContext write = new(options);
        await write.Database.MigrateAsync();
        write.Hotstrings.Add(first);
        await write.SaveChangesAsync();

        write.Hotstrings.Add(second);
        Func<Task> act = async () => await write.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }
}
