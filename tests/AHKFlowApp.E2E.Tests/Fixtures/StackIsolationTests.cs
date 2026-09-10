using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Proves the isolation boundary the four parallel stacks depend on.
/// </summary>
/// <remarks>
/// Every flow test resets its own stack's rows before it starts. The four stacks run at the same
/// time, so a reset in one stack must not touch another stack's rows. ApiFactoryTests proves the
/// names differ; this proves the databases behind those names really are separate.
/// </remarks>
[Collection(ExclusiveTestCollection.Name)]
public sealed class StackIsolationTests
{
    [Fact]
    public async Task ResettingOneStack_LeavesTheOtherStacksRowsInPlace()
    {
        // Arrange
        StackFixture reset = new("AHKFlowApp.E2E.Tests.IsolationReset");
        StackFixture keep = new("AHKFlowApp.E2E.Tests.IsolationKeep");

        try
        {
            await reset.Api.StartAsync();
            await keep.Api.StartAsync();

            await reset.ResetDataAsync();
            await keep.ResetDataAsync();

            await AddCategoryAsync(reset, "isolation-reset-stack");
            await AddCategoryAsync(keep, "isolation-keep-stack");

            // Act
            await reset.ResetDataAsync();

            // Assert
            (await CategoryNamesAsync(reset)).Should().BeEmpty(
                "a reset clears the rows of the stack it runs on");
            (await CategoryNamesAsync(keep)).Should().ContainSingle()
                .Which.Should().Be(
                    "isolation-keep-stack",
                    "a reset in one stack must not reach another stack's database");
        }
        finally
        {
            await reset.Api.DisposeAsync();
            await keep.Api.DisposeAsync();
        }
    }

    private static async Task AddCategoryAsync(StackFixture stack, string name)
    {
        await using AsyncServiceScope scope = stack.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.Categories.Add(Category.Create(Guid.NewGuid(), name, TimeProvider.System));
        await db.SaveChangesAsync();
    }

    private static async Task<string[]> CategoryNamesAsync(StackFixture stack)
    {
        await using AsyncServiceScope scope = stack.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        return await db.Categories.AsNoTracking().Select(category => category.Name).ToArrayAsync();
    }
}
