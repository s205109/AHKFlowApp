using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class EntityHistoryTests
{
    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    [Fact]
    public void Create_SetsAllFieldsAndCapturedAtFromClock()
    {
        var ownerOid = Guid.NewGuid();
        var entityId = Guid.NewGuid();
        var now = DateTimeOffset.Parse("2026-07-01T10:00:00Z");

        var entry = EntityHistory.Create(
            ownerOid, TrackedEntityType.Hotstring, entityId, 3,
            HistoryChangeType.Edit, 1, "{}", new FixedClock(now));

        entry.Id.Should().NotBeEmpty();
        entry.OwnerOid.Should().Be(ownerOid);
        entry.EntityType.Should().Be(TrackedEntityType.Hotstring);
        entry.EntityId.Should().Be(entityId);
        entry.Version.Should().Be(3);
        entry.ChangeType.Should().Be(HistoryChangeType.Edit);
        entry.SchemaVersion.Should().Be(1);
        entry.SnapshotJson.Should().Be("{}");
        entry.CapturedAt.Should().Be(now);
    }

    [Fact]
    public void ReassignVersion_ReplacesVersion()
    {
        var entry = EntityHistory.Create(
            Guid.NewGuid(), TrackedEntityType.Hotkey, Guid.NewGuid(), 1,
            HistoryChangeType.Delete, 1, "{}", TimeProvider.System);

        entry.ReassignVersion(7);

        entry.Version.Should().Be(7);
    }
}
