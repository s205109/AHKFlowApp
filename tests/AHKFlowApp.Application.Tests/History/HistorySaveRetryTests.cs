using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class HistorySaveRetryTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task SaveWithHistoryRetryAsync_VersionCollision_BumpsVersionAndSaves()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        await using (AppDbContext rival = fx.CreateContext())
        {
            rival.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await rival.SaveChangesAsync();
        }

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(2);
        (await db.EntityHistories.CountAsync(h => h.EntityId == entityId)).Should().Be(2);
    }

    [Fact]
    public async Task SaveWithHistoryRetryAsync_NoCollision_SavesNormally()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var entry = EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System);
        db.EntityHistories.Add(entry);

        await db.SaveWithHistoryRetryAsync(entry, default);

        entry.Version.Should().Be(1);
    }
}
