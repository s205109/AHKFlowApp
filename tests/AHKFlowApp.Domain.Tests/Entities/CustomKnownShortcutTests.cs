using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class CustomKnownShortcutTests
{
    private static readonly Guid Owner = Guid.NewGuid();

    [Fact]
    public void Create_StampsBothTimesFromTheClock()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 7, 29, 10, 0, 0, TimeSpan.Zero));

        var record = CustomKnownShortcut.Create(
            Owner, "K", ctrl: true, alt: false, shift: false, win: false,
            "Visual Studio", ShortcutProtection.Normal, ShortcutScope.Foreground,
            "open the comment menu", clock);

        record.OwnerOid.Should().Be(Owner);
        record.CreatedAt.Should().Be(clock.GetUtcNow());
        record.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void Update_MovesUpdatedAtOnly()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 7, 29, 10, 0, 0, TimeSpan.Zero));
        var record = CustomKnownShortcut.Create(
            Owner, "K", true, false, false, false,
            "Visual Studio", ShortcutProtection.Normal, ShortcutScope.Foreground, "open the menu", clock);
        DateTimeOffset created = record.CreatedAt;

        clock.Advance(TimeSpan.FromMinutes(5));
        record.Update("Visual Studio Code", ShortcutProtection.Unknown, ShortcutScope.Foreground,
            "open the command palette", clock);

        record.CreatedAt.Should().Be(created);
        record.UpdatedAt.Should().Be(clock.GetUtcNow());
        record.UsedBy.Should().Be("Visual Studio Code");
        record.Does.Should().Be("open the command palette");
    }
}
