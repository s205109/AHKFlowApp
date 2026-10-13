using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Migrations;

public sealed class BackfillEmptyProfileHeadersTests(SharedSqlServerFixture sqlFixture)
    : IClassFixture<SharedSqlServerFixture>
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
    public async Task Backfill_FillsAnEmptyHeader_AndLeavesEveryWrittenHeaderAlone()
    {
        var owner = Guid.NewGuid();
        var emptyHeader = Guid.NewGuid();
        var ownHeader = Guid.NewGuid();
        var spacesOnly = Guid.NewGuid();

        DateTimeOffset updatedAtBefore;

        await using (AppDbContext setup = CreateContext("BackfillEmptyProfileHeaders"))
        {
            // Drop first, then apply every migration up to but not including this one. The drop is
            // what keeps this fact working on a server an earlier run already used.
            await RunIndependentDatabase.DropThenMigrateToAsync(setup, "AddHotkeyWindowContext");

            // Three rows, one per case the repair has to get right. Interpolated values bind as
            // parameters; SQL literals stay quoted inline.
            await setup.Database.ExecuteSqlAsync($"""
                INSERT INTO Profiles (Id, OwnerOid, Name, HeaderTemplate, FooterTemplate, IsDefault, CreatedAt, UpdatedAt)
                VALUES ({emptyHeader}, {owner}, 'Made in the web UI', '', '', 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO Profiles (Id, OwnerOid, Name, HeaderTemplate, FooterTemplate, IsDefault, CreatedAt, UpdatedAt)
                VALUES ({ownHeader}, {owner}, 'Header the owner wrote', '; my own header', '', 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

                INSERT INTO Profiles (Id, OwnerOid, Name, HeaderTemplate, FooterTemplate, IsDefault, CreatedAt, UpdatedAt)
                VALUES ({spacesOnly}, {owner}, 'Two spaces', '  ', '', 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
                """);

            // Read UpdatedAt back before the repair runs. The repair must leave that column alone,
            // so the test has to know what it held. Read it rather than compute it:
            // SYSDATETIMEOFFSET() runs on the server, so no value known here matches it.
            updatedAtBefore =
                (await setup.Profiles.AsNoTracking().SingleAsync(p => p.Id == emptyHeader)).UpdatedAt;

            // Apply the remaining migration. This is the one under test.
            await setup.Database.MigrateAsync();
        }

        await using AppDbContext verify = CreateContext("BackfillEmptyProfileHeaders");

        // The repair writes the default header, byte for byte. Comparing against the constant is
        // the strongest check available today. If anybody ever changes the default header text,
        // this migration must keep writing the old text, so replace this expectation with the
        // literal the migration holds, and say in a comment that it is frozen on purpose.
        Profile repairedProfile = await verify.Profiles.SingleAsync(p => p.Id == emptyHeader);
        repairedProfile.HeaderTemplate.Should().Be(DefaultProfileTemplates.Header);

        // The repair does not touch UpdatedAt. The profiles table shows that value to the owner,
        // so bumping it would tell them they edited the profile on the day of the deploy. This
        // assertion is what stops a later edit of the migration adding an UpdatedAt write.
        repairedProfile.UpdatedAt.Should().Be(updatedAtBefore);

        // A header the owner wrote survives untouched. This is the property that also makes the
        // migration safe to run twice: after it runs, no row holds a zero-length header, so a
        // second run matches nothing.
        (await verify.Profiles.SingleAsync(p => p.Id == ownHeader))
            .HeaderTemplate.Should().Be("; my own header");

        // Two spaces are text, so they stay. This is why the migration tests DATALENGTH and not
        // equality with an empty string: SQL Server pads strings before it compares them, so
        // N'  ' = N'' is true, and an equality test would have overwritten this row.
        // https://learn.microsoft.com/sql/t-sql/language-elements/string-comparison-assignment
        (await verify.Profiles.SingleAsync(p => p.Id == spacesOnly))
            .HeaderTemplate.Should().Be("  ");
    }
}
