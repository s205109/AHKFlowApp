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

[Collection("SqlServer")]
public sealed class SchemaPolishBackfillTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateContext(string databaseName)
    {
        SqlConnectionStringBuilder csb = new(sqlFixture.ConnectionString) { InitialCatalog = databaseName };

        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        return new AppDbContext(options);
    }

    [Fact]
    public async Task SchemaPolish_RemovesInconsistentProfileAssociations()
    {
        var owner = Guid.NewGuid();
        var profileId = Guid.NewGuid();
        var hotstringAllWithJunction = Guid.NewGuid();
        var hotstringScopedNoJunction = Guid.NewGuid();
        var hotkeyAllWithJunction = Guid.NewGuid();
        var hotkeyScopedNoJunction = Guid.NewGuid();

        await using (AppDbContext setup = CreateContext("SchemaPolish_Backfill"))
        {
            // Apply every migration up to but not including SchemaPolish.
            IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup).Instance.GetRequiredService<IMigrator>();
            await migrator.MigrateAsync("Phase3HotkeyRebuild");

            // Seed intentionally-inconsistent rows directly via SQL — the EF model already
            // has the Description column, so entity inserts would fail before SchemaPolish runs.
            // Interpolated GUIDs bind as parameters; SQL literals stay quoted inline.
            await setup.Database.ExecuteSqlAsync($"""
                INSERT INTO Profiles (Id, OwnerOid, Name, HeaderTemplate, FooterTemplate, IsDefault, CreatedAt, UpdatedAt)
                VALUES ({profileId}, {owner}, 'Seed Profile', '', '', 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO Hotstrings (Id, OwnerOid, [Trigger], Replacement, AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord, CreatedAt, UpdatedAt)
                VALUES ({hotstringAllWithJunction}, {owner}, 'seedall', 'x', 1, 1, 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO Hotstrings (Id, OwnerOid, [Trigger], Replacement, AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord, CreatedAt, UpdatedAt)
                VALUES ({hotstringScopedNoJunction}, {owner}, 'seedscoped', 'y', 0, 1, 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO HotstringProfiles (HotstringId, ProfileId) VALUES ({hotstringAllWithJunction}, {profileId});

                INSERT INTO Hotkeys (Id, OwnerOid, [Action], Alt, Ctrl, Shift, Win, [Key], Parameters, Description, AppliesToAllProfiles, CreatedAt, UpdatedAt)
                VALUES ({hotkeyAllWithJunction}, {owner}, 0, 0, 1, 0, 0, 'F1', '', 'seed', 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO Hotkeys (Id, OwnerOid, [Action], Alt, Ctrl, Shift, Win, [Key], Parameters, Description, AppliesToAllProfiles, CreatedAt, UpdatedAt)
                VALUES ({hotkeyScopedNoJunction}, {owner}, 0, 0, 1, 0, 0, 'F2', '', 'seed', 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO HotkeyProfiles (HotkeyId, ProfileId) VALUES ({hotkeyAllWithJunction}, {profileId});
                """);

            // Apply the remaining migration — SchemaPolish runs the four backfill statements.
            await setup.Database.MigrateAsync();
        }

        await using AppDbContext verify = CreateContext("SchemaPolish_Backfill");

        int inconsistentHotstrings = await verify.Hotstrings.CountAsync(h =>
            (h.AppliesToAllProfiles && h.Profiles.Any())
            || (!h.AppliesToAllProfiles && !h.Profiles.Any()));
        inconsistentHotstrings.Should().Be(0);

        int inconsistentHotkeys = await verify.Hotkeys.CountAsync(h =>
            (h.AppliesToAllProfiles && h.Profiles.Any())
            || (!h.AppliesToAllProfiles && !h.Profiles.Any()));
        inconsistentHotkeys.Should().Be(0);

        // The backfill removes junction rows and flips flags — it never deletes the entities themselves.
        (await verify.Hotstrings.CountAsync()).Should().Be(2);
        (await verify.Hotkeys.CountAsync()).Should().Be(2);

        // The scoped-but-orphaned rows were flipped to AppliesToAllProfiles = true.
        (await verify.Hotstrings.SingleAsync(h => h.Id == hotstringScopedNoJunction))
            .AppliesToAllProfiles.Should().BeTrue();
        (await verify.Hotkeys.SingleAsync(h => h.Id == hotkeyScopedNoJunction))
            .AppliesToAllProfiles.Should().BeTrue();
    }
}
