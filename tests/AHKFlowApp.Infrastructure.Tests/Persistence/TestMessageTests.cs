using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class TestMessageTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateMigratedContext(string databaseName)
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString) { InitialCatalog = databaseName };
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(csb.ConnectionString, sql => sql.EnableRetryOnFailure())
            .Options;
        var context = new AppDbContext(options);
        context.Database.Migrate();
        return context;
    }

    [Fact]
    public async Task Add_TestMessage_PersistsMessage()
    {
        // Arrange
        await using AppDbContext context = CreateMigratedContext("TestMessageTests_Persist");
        var message = new TestMessage { Message = "hello", CreatedAt = DateTime.UtcNow };

        // Act
        context.TestMessages.Add(message);
        await context.SaveChangesAsync();

        // Assert
        await using AppDbContext readContext = CreateMigratedContext("TestMessageTests_Persist");
        TestMessage? saved = await readContext.TestMessages.FindAsync(message.Id);
        saved.Should().NotBeNull();
        saved!.Message.Should().Be("hello");
    }

    [Fact]
    public async Task Add_TestMessage_PersistsCreatedAt()
    {
        // Arrange
        await using AppDbContext context = CreateMigratedContext("TestMessageTests_CreatedAt");
        DateTime now = DateTime.UtcNow;
        var message = new TestMessage { Message = "ts-test", CreatedAt = now };

        // Act
        context.TestMessages.Add(message);
        await context.SaveChangesAsync();

        // Assert
        await using AppDbContext readContext = CreateMigratedContext("TestMessageTests_CreatedAt");
        TestMessage? saved = await readContext.TestMessages.FindAsync(message.Id);
        saved.Should().NotBeNull();
        saved!.CreatedAt.Should().BeCloseTo(now, TimeSpan.FromSeconds(1));
    }
}
