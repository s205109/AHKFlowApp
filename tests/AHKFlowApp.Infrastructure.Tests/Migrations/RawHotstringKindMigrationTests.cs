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
/// Proves the migration's hand-written Script→Raw T-SQL agrees byte-for-byte with
/// <c>ScriptToRawComposer</c>: every golden fixture is seeded as a legacy Script row (Kind = 3)
/// before the migration runs, then its migrated Replacement must equal the composer's expected
/// verbatim definition, with Kind flipped to Raw (4). Includes the 4,000-character body row,
/// proving the widened column does not truncate.
/// </summary>
[Collection("SqlServer")]
public sealed class RawHotstringKindMigrationTests(SqlContainerFixture sqlFixture)
{
    private const string DbName = "RawHotstringKind_Parity";

    private AppDbContext CreateContext()
    {
        SqlConnectionStringBuilder csb = new(sqlFixture.ConnectionString) { InitialCatalog = DbName };

        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;

        return new AppDbContext(options);
    }

    [Fact]
    public async Task Migration_RewritesLegacyScriptRows_ByteIdenticalToComposer()
    {
        Dictionary<Guid, ScriptToRawFixture> seeded = [];

        await using (AppDbContext setup = CreateContext())
        {
            // Apply every migration up to but not including RawHotstringKind, so the Hotstrings
            // table still has the body-only nvarchar(4000) Replacement column.
            IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup).Instance.GetRequiredService<IMigrator>();
            await migrator.MigrateAsync("AddHotstringWindowContext");

            foreach (ScriptToRawFixture f in ScriptToRawFixtures.All)
            {
                var id = Guid.NewGuid();
                // Unique owner per row so duplicate triggers (e.g. "t") don't hit the unique index.
                var owner = Guid.NewGuid();
                seeded[id] = f;

                await setup.Database.ExecuteSqlRawAsync(
                    """
                    INSERT INTO Hotstrings
                        (Id, OwnerOid, [Trigger], Replacement, AppliesToAllProfiles,
                         IsEndingCharacterRequired, IsTriggerInsideWord, Kind, IsCaseSensitive,
                         OmitEndingCharacter, CreatedAt, UpdatedAt)
                    VALUES
                        (@id, @owner, @trigger, @body, 1,
                         @ending, @inside, 3, @case,
                         @omit, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
                    """,
                    new SqlParameter("@id", id),
                    new SqlParameter("@owner", owner),
                    new SqlParameter("@trigger", f.Trigger),
                    new SqlParameter("@body", f.Body),
                    new SqlParameter("@ending", f.IsEndingCharacterRequired),
                    new SqlParameter("@inside", f.IsTriggerInsideWord),
                    new SqlParameter("@case", f.IsCaseSensitive),
                    new SqlParameter("@omit", f.OmitEndingCharacter));
            }

            // Apply RawHotstringKind — widen column + rewrite Kind=3 rows.
            await setup.Database.MigrateAsync();
        }

        await using AppDbContext verify = CreateContext();

        foreach ((Guid id, ScriptToRawFixture f) in seeded)
        {
            Domain.Entities.Hotstring row = await verify.Hotstrings.AsNoTracking().SingleAsync(h => h.Id == id);

            row.Kind.Should().Be(Domain.Enums.HotstringKind.Raw, "fixture '{0}' should convert to Raw", f.Name);
            row.Replacement.Should().Be(f.ExpectedRawDefinition, "fixture '{0}' must match the composer output", f.Name);
        }
    }
}
