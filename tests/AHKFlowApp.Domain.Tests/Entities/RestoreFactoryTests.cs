using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class RestoreFactoryTests
{
    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    [Fact]
    public void HotstringRestore_KeepsOriginalIdAndCreatedAt_SetsUpdatedAtFromClock()
    {
        var id = Guid.NewGuid();
        var ownerOid = Guid.NewGuid();
        var createdAt = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        var now = DateTimeOffset.Parse("2026-07-01T10:00:00Z");

        var entity = Hotstring.Restore(
            id, ownerOid,
            new HotstringDefinition(
                "btw", "by the way", "desc",
                AppliesToAllProfiles: false, IsEndingCharacterRequired: true,
                IsTriggerInsideWord: false),
            createdAt, new FixedClock(now));

        entity.Id.Should().Be(id);
        entity.OwnerOid.Should().Be(ownerOid);
        entity.Trigger.Should().Be("btw");
        entity.Replacement.Should().Be("by the way");
        entity.Description.Should().Be("desc");
        entity.AppliesToAllProfiles.Should().BeFalse();
        entity.IsEndingCharacterRequired.Should().BeTrue();
        entity.IsTriggerInsideWord.Should().BeFalse();
        entity.CreatedAt.Should().Be(createdAt);
        entity.UpdatedAt.Should().Be(now);
    }

    [Fact]
    public void HotkeyRestore_KeepsOriginalIdAndCreatedAt_SetsUpdatedAtFromClock()
    {
        var id = Guid.NewGuid();
        var ownerOid = Guid.NewGuid();
        var createdAt = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        var now = DateTimeOffset.Parse("2026-07-01T10:00:00Z");

        var entity = Hotkey.Restore(
            id, ownerOid,
            new HotkeyDefinition(
                Description: "Open terminal", Key: "T",
                Ctrl: true, Alt: false, Shift: true, Win: false,
                Action: HotkeyAction.Run, Parameters: "wt.exe",
                AppliesToAllProfiles: true),
            createdAt, new FixedClock(now));

        entity.Id.Should().Be(id);
        entity.OwnerOid.Should().Be(ownerOid);
        entity.Description.Should().Be("Open terminal");
        entity.Key.Should().Be("T");
        entity.Ctrl.Should().BeTrue();
        entity.Shift.Should().BeTrue();
        entity.Action.Should().Be(HotkeyAction.Run);
        entity.Parameters.Should().Be("wt.exe");
        entity.AppliesToAllProfiles.Should().BeTrue();
        entity.CreatedAt.Should().Be(createdAt);
        entity.UpdatedAt.Should().Be(now);
    }
}
