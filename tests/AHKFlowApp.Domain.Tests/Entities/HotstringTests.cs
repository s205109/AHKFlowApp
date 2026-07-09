using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
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

        var hs = Hotstring.Create(
            owner, new HotstringDefinition("btw", "by the way", null, true, true, false), _clock);

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
        var hs = Hotstring.Create(
            Guid.NewGuid(), new HotstringDefinition("x", "y", null, false, true, true), _clock);

        hs.AppliesToAllProfiles.Should().BeFalse();
    }

    [Fact]
    public void Update_ChangesAllMutableFields()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var hs = Hotstring.Create(
            Guid.NewGuid(), new HotstringDefinition("old", "old replacement", null, true, true, false), clock);

        clock.Advance(TimeSpan.FromMinutes(1));
        hs.Update(new HotstringDefinition("new", "new replacement", null, false, false, true), clock);

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
        var hs = Hotstring.Create(
            Guid.NewGuid(), new HotstringDefinition("x", "y", null, false, true, true), clock);

        hs.Update(new HotstringDefinition("x", "y", null, true, true, true), clock);

        hs.AppliesToAllProfiles.Should().BeTrue();
    }

    [Fact]
    public void Create_RoundTripsDescription()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
        var h = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition(
                Trigger: "btw",
                Replacement: "by the way",
                Description: "polite filler",
                AppliesToAllProfiles: true,
                IsEndingCharacterRequired: true,
                IsTriggerInsideWord: false),
            clock);

        h.Description.Should().Be("polite filler");
    }

    [Fact]
    public void Create_AcceptsNullDescription()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
        var h = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition(
                Trigger: "btw",
                Replacement: "by the way",
                Description: null,
                AppliesToAllProfiles: true,
                IsEndingCharacterRequired: true,
                IsTriggerInsideWord: false),
            clock);

        h.Description.Should().BeNull();
    }

    [Fact]
    public void Update_RoundTripsDescription()
    {
        FakeTimeProvider clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
        var h = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition("btw", "by the way", null, true, true, false),
            clock);

        clock.Advance(TimeSpan.FromHours(1));
        h.Update(new HotstringDefinition("btw", "by the way!", "updated", true, true, false), clock);

        h.Description.Should().Be("updated");
        h.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Create_DefaultDefinition_IsTextKindWithNewFlagsOff()
    {
        var hs = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition("btw", "by the way", null, true, true, false),
            _clock);

        hs.Kind.Should().Be(HotstringKind.Text);
        hs.IsCaseSensitive.Should().BeFalse();
        hs.OmitEndingCharacter.Should().BeFalse();
    }

    [Fact]
    public void Create_WithNewOptions_SetsKindAndFlags()
    {
        var hs = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition("btw", "by the way", null, true, true, false,
                HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true),
            _clock);

        hs.IsCaseSensitive.Should().BeTrue();
        hs.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public void Update_WithNewOptions_OverwritesFlags()
    {
        var hs = Hotstring.Create(
            Guid.NewGuid(), new HotstringDefinition("x", "y", null, true, true, false), _clock);

        hs.Update(new HotstringDefinition("x", "y", null, true, true, false,
            HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true), _clock);

        hs.IsCaseSensitive.Should().BeTrue();
        hs.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public void Restore_WithNewOptions_RehydratesFlags()
    {
        DateTimeOffset createdAt = DateTimeOffset.UtcNow.AddDays(-1);

        var hs = Hotstring.Restore(
            Guid.NewGuid(), Guid.NewGuid(),
            new HotstringDefinition("x", "y", null, true, true, false,
                HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: true),
            createdAt, _clock);

        hs.CreatedAt.Should().Be(createdAt);
        hs.IsCaseSensitive.Should().BeTrue();
        hs.OmitEndingCharacter.Should().BeTrue();
    }

    [Fact]
    public void Create_RoundTripsDateTimeFields()
    {
        var hs = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition("btw", "by the way", null, true, true, false,
                HotstringKind.DateTime, DateTimeFormat: "yyyy-MM-dd",
                DateOffsetAmount: 3, DateOffsetUnit: DateOffsetUnit.Days),
            _clock);

        hs.DateTimeFormat.Should().Be("yyyy-MM-dd");
        hs.DateOffsetAmount.Should().Be(3);
        hs.DateOffsetUnit.Should().Be(DateOffsetUnit.Days);
    }

    [Fact]
    public void Create_DefaultDefinition_HasNullDateTimeFields()
    {
        var hs = Hotstring.Create(
            Guid.NewGuid(),
            new HotstringDefinition("btw", "by the way", null, true, true, false),
            _clock);

        hs.DateTimeFormat.Should().BeNull();
        hs.DateOffsetAmount.Should().BeNull();
        hs.DateOffsetUnit.Should().BeNull();
    }

    [Fact]
    public void Update_RoundTripsDateTimeFields()
    {
        var hs = Hotstring.Create(
            Guid.NewGuid(), new HotstringDefinition("x", "y", null, true, true, false), _clock);

        hs.Update(new HotstringDefinition("x", "y", null, true, true, false,
            HotstringKind.DateTime, DateTimeFormat: "HH:mm:ss",
            DateOffsetAmount: -1, DateOffsetUnit: DateOffsetUnit.Hours), _clock);

        hs.DateTimeFormat.Should().Be("HH:mm:ss");
        hs.DateOffsetAmount.Should().Be(-1);
        hs.DateOffsetUnit.Should().Be(DateOffsetUnit.Hours);
    }

    [Fact]
    public void Restore_RoundTripsDateTimeFields()
    {
        DateTimeOffset createdAt = DateTimeOffset.UtcNow.AddDays(-2);

        var hs = Hotstring.Restore(
            Guid.NewGuid(), Guid.NewGuid(),
            new HotstringDefinition("x", "y", null, true, true, false,
                HotstringKind.DateTime, DateTimeFormat: "MMMM d",
                DateOffsetAmount: 30, DateOffsetUnit: DateOffsetUnit.Minutes),
            createdAt, _clock);

        hs.CreatedAt.Should().Be(createdAt);
        hs.DateTimeFormat.Should().Be("MMMM d");
        hs.DateOffsetAmount.Should().Be(30);
        hs.DateOffsetUnit.Should().Be(DateOffsetUnit.Minutes);
    }
}
