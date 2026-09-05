using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Migrations;

/// <summary>
/// Proves the HotkeyTypedActions migration's hand-written back-fill T-SQL agrees with
/// <c>LegacyHotkeyDefinitionConverter</c> over every <c>LegacyHotkeyFixtures</c> row.
/// </summary>
public sealed class HotkeyTypedActionsMigrationTests(SharedSqlServerFixture sqlFixture)
    : IClassFixture<SharedSqlServerFixture>
{
    private const string DbName = "HotkeyTypedActions_Parity";
    private const string DivergenceDbName = "HotkeyTypedActions_Divergence";

    // Each fact migrates from scratch, so each needs its own database.
    private AppDbContext CreateContext(string dbName = DbName)
    {
        SqlConnectionStringBuilder csb = new(sqlFixture.ConnectionString) { InitialCatalog = dbName };

        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        return new AppDbContext(options);
    }

    [Fact]
    public async Task Migration_BackfillsTypedColumns_MatchingConverter()
    {
        Dictionary<Guid, LegacyHotkeyFixture> seeded = [];

        await using (AppDbContext setup = CreateContext())
        {
            // Migrate up to the migration immediately before HotkeyTypedActions.
            IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup).Instance.GetRequiredService<IMigrator>();
            await migrator.MigrateAsync("AddHotstringDelivery");

            foreach (LegacyHotkeyFixture f in LegacyHotkeyFixtures.All)
            {
                var id = Guid.NewGuid();
                var owner = Guid.NewGuid(); // unique owner so duplicate key+mods don't collide
                seeded[id] = f;

                await setup.Database.ExecuteSqlRawAsync(
                    """
                    INSERT INTO Hotkeys
                        (Id, OwnerOid, Description, [Key], Ctrl, Alt, Shift, Win,
                         Action, Parameters, AppliesToAllProfiles, CreatedAt, UpdatedAt)
                    VALUES
                        (@id, @owner, @descr, 'a', 0, 0, 0, 0,
                         @action, @params, 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
                    """,
                    new SqlParameter("@id", id),
                    new SqlParameter("@owner", owner),
                    new SqlParameter("@descr", f.Name),
                    new SqlParameter("@action", (int)f.Action),
                    new SqlParameter("@params", f.Parameters));
            }

            await setup.Database.MigrateAsync(); // apply HotkeyTypedActions
        }

        await using AppDbContext verify = CreateContext();

        foreach ((Guid id, LegacyHotkeyFixture f) in seeded)
        {
            Domain.Entities.Hotkey row = await verify.Hotkeys.AsNoTracking().SingleAsync(h => h.Id == id);
            LegacyHotkeyDefinitionConverter.TypedAction expected =
                LegacyHotkeyDefinitionConverter.ToTyped(f.Action, f.Parameters);

            row.ActionKind.Should().Be(expected.ActionKind, "fixture '{0}'", f.Name);
            row.Text.Should().Be(expected.Text, "fixture '{0}'", f.Name);
            row.SendKeysContent.Should().Be(expected.SendKeysContent, "fixture '{0}'", f.Name);
            row.RunTarget.Should().Be(expected.RunTarget, "fixture '{0}'", f.Name);
            row.RunTargetKind.Should().Be(expected.RunTargetKind, "fixture '{0}'", f.Name);
            row.WindowOp.Should().Be(expected.WindowOp, "fixture '{0}'", f.Name);
            row.RemapDest.Should().Be(expected.RemapDest, "fixture '{0}'", f.Name);
            row.Body.Should().Be(expected.Body, "fixture '{0}'", f.Name);
        }
    }

    // LControl was added to HotkeyKeys after this migration shipped, so its frozen name list does
    // not hold it and LegacyHotkeyFixtures skips it. The parity test therefore never seeds this
    // value. Pin what the migration actually does with it, so the divergence ADR 0004 records is a
    // tested decision rather than an untested paragraph.
    [Fact]
    public async Task Migration_SpellingAddedAfterItShipped_StaysRaw()
    {
        var id = Guid.NewGuid();

        await using (AppDbContext setup = CreateContext(DivergenceDbName))
        {
            IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup).Instance.GetRequiredService<IMigrator>();
            await migrator.MigrateAsync("AddHotstringDelivery");

            // Legacy Action: Send = 0, Run = 1. Parameters is a SQL parameter, not embedded in the
            // literal text — ExecuteSqlRawAsync treats the raw SQL as a composite format string, and
            // a literal '{LControl}' in the text would be misread as a format placeholder.
            await setup.Database.ExecuteSqlRawAsync(
                """
                INSERT INTO Hotkeys
                    (Id, OwnerOid, Description, [Key], Ctrl, Alt, Shift, Win,
                     Action, Parameters, AppliesToAllProfiles, CreatedAt, UpdatedAt)
                VALUES
                    (@id, @owner, 'legacy LControl', 'a', 0, 0, 0, 0,
                     0, @params, 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
                """,
                new SqlParameter("@id", id),
                new SqlParameter("@owner", Guid.NewGuid()),
                new SqlParameter("@params", "{LControl}"));

            await setup.Database.MigrateAsync();
        }

        await using AppDbContext verify = CreateContext(DivergenceDbName);
        Domain.Entities.Hotkey row = await verify.Hotkeys.AsNoTracking().SingleAsync(h => h.Id == id);

        row.ActionKind.Should().Be(HotkeyActionKind.Raw);
        row.Body.Should().Be("""Send("{LControl}")""");
        row.SendKeysContent.Should().BeNull();
    }
}
