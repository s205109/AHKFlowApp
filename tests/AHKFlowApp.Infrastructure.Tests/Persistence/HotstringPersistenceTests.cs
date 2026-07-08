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
}
