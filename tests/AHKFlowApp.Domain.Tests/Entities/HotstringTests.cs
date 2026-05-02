using AHKFlowApp.Domain.Entities;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class HotstringTests
{
    private static readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public void Create_WithAppliesToAllProfiles_SetsAllProperties()
    {
        var owner = Guid.NewGuid();

        var hs = Hotstring.Create(owner, "btw", "by the way", appliesToAllProfiles: true, true, false, _clock);

        hs.Id.Should().NotBeEmpty();
        hs.OwnerOid.Should().Be(owner);
        hs.Trigger.Should().Be("btw");
        hs.Replacement.Should().Be("by the way");
        hs.AppliesToAllProfiles.Should().BeTrue();
        hs.Profiles.Should().BeEmpty();
        hs.IsEndingCharacterRequired.Should().BeTrue();
        hs.IsTriggerInsideWord.Should().BeFalse();
        hs.CreatedAt.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromSeconds(5));
        hs.UpdatedAt.Should().Be(hs.CreatedAt);
    }

    [Fact]
    public void Create_WithAppliesToAllProfilesFalse_SetsProperty()
    {
        var hs = Hotstring.Create(Guid.NewGuid(), "x", "y", appliesToAllProfiles: false, true, true, _clock);

        hs.AppliesToAllProfiles.Should().BeFalse();
    }

    [Fact]
    public void Update_ChangesAllMutableFields()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var hs = Hotstring.Create(Guid.NewGuid(), "old", "old replacement", appliesToAllProfiles: true, true, false, clock);

        clock.Advance(TimeSpan.FromMinutes(1));
        hs.Update("new", "new replacement", appliesToAllProfiles: false, false, true, clock);

        hs.Trigger.Should().Be("new");
        hs.Replacement.Should().Be("new replacement");
        hs.AppliesToAllProfiles.Should().BeFalse();
        hs.IsEndingCharacterRequired.Should().BeFalse();
        hs.IsTriggerInsideWord.Should().BeTrue();
        hs.UpdatedAt.Should().BeAfter(hs.CreatedAt);
    }

    [Fact]
    public void Update_WithAppliesToAllProfiles_SetsFlag()
    {
        TimeProvider clock = TimeProvider.System;
        var hs = Hotstring.Create(Guid.NewGuid(), "x", "y", appliesToAllProfiles: false, true, true, clock);

        hs.Update("x", "y", appliesToAllProfiles: true, true, true, clock);

        hs.AppliesToAllProfiles.Should().BeTrue();
    }
}
