using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
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
public sealed class HotstringDeliveryMigrationTests(SqlContainerFixture sqlFixture)
{
    private const string DbName = "HotstringDelivery_DefaultAuto";

    private AppDbContext CreateContext()
    {
        SqlConnectionStringBuilder csb = new(sqlFixture.ConnectionString) { InitialCatalog = DbName };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;
        return new AppDbContext(options);
    }

    [Fact]
    public async Task Migration_ExistingLongTextDefaultsToAutoAndEmitsClipboardPaste()
    {
        var id = Guid.NewGuid();
        var owner = Guid.NewGuid();
        string replacement = new('x', 200);

        await using (AppDbContext setup = CreateContext())
        {
            IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup)
                .Instance.GetRequiredService<IMigrator>();
            await migrator.MigrateAsync("RawHotstringKind");
            await setup.Database.ExecuteSqlRawAsync(
                """
                INSERT INTO Hotstrings
                    (Id, OwnerOid, [Trigger], Replacement, AppliesToAllProfiles,
                     IsEndingCharacterRequired, IsTriggerInsideWord, Kind, IsCaseSensitive,
                     OmitEndingCharacter, CreatedAt, UpdatedAt)
                VALUES
                    (@id, @owner, 'legacy-long', @replacement, 1,
                     1, 0, 0, 0,
                     0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
                """,
                new SqlParameter("@id", id),
                new SqlParameter("@owner", owner),
                new SqlParameter("@replacement", replacement));

            await setup.Database.MigrateAsync();
        }

        await using AppDbContext verify = CreateContext();
        Hotstring row = await verify.Hotstrings.AsNoTracking().SingleAsync(h => h.Id == id);
        Profile profile = new ProfileBuilder().WithOwner(owner).WithHeader("H").WithFooter("F").Build();
        var generator = new AhkScriptGenerator(
            new HeaderTokenRenderer(), TimeProvider.System, new TestVersionProvider());

        string script = generator.Generate(profile, [row], []);

        row.Delivery.Should().Be(HotstringDelivery.Auto);
        script.Should().Contain("AhkFlow_PasteReplacement(text");
        script.Should().Contain(":X:legacy-long::AhkFlow_PasteReplacement(");
    }

    private sealed class TestVersionProvider : IAppVersionProvider
    {
        public string GetVersion() => "test";
    }
}
