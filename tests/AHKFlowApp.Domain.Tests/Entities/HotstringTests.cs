using AHKFlowApp.Domain.Entities;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class HotstringTests
{
    private static readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public void Create_WithValidArgs_SetsAllProperties()
    {
        var owner = Guid.NewGuid();

        var hs = Hotstring.Create(owner, "btw", "by the way", null, true, false, _clock);

        hs.Id.Should().NotBeEmpty();
        hs.OwnerOid.Should().Be(owner);
        hs.Trigger.Should().Be("btw");
        hs.Replacement.Should().Be("by the way");
        hs.ProfileId.Should().BeNull();
        hs.IsEndingCharacterRequired.Should().BeTrue();
        hs.IsTriggerInsideWord.Should().BeFalse();
        hs.CreatedAt.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromSeconds(5));
        hs.UpdatedAt.Should().Be(hs.CreatedAt);
    }

    [Fact]
    public void Create_WithProfileId_SetsProfileId()
    {
        var profileId = Guid.NewGuid();

        var hs = Hotstring.Create(Guid.NewGuid(), "x", "y", profileId, true, true, _clock);

        hs.ProfileId.Should().Be(profileId);
    }

    [Fact]
    public void Update_ChangesAllMutableFields()
    {
        var clock = new FakeTimeProvider(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var hs = Hotstring.Create(Guid.NewGuid(), "old", "old replacement", null, true, false, clock);

        clock.Advance(TimeSpan.FromMinutes(1));
        hs.Update("new", "new replacement", Guid.NewGuid(), false, true, clock);

        hs.Trigger.Should().Be("new");
        hs.Replacement.Should().Be("new replacement");
        hs.ProfileId.Should().NotBeNull();
        hs.IsEndingCharacterRequired.Should().BeFalse();
        hs.IsTriggerInsideWord.Should().BeTrue();
        hs.UpdatedAt.Should().BeAfter(hs.CreatedAt);
    }

    [Fact]
    public void Update_WithNullProfileId_ClearsProfile()
    {
        TimeProvider clock = TimeProvider.System;
        var hs = Hotstring.Create(Guid.NewGuid(), "x", "y", Guid.NewGuid(), true, true, clock);

        hs.Update("x", "y", null, true, true, clock);

        hs.ProfileId.Should().BeNull();
    }
}
