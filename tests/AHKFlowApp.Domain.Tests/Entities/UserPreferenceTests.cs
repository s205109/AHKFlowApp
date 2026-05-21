using AHKFlowApp.Domain.Entities;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Entities;

public sealed class UserPreferenceTests
{
    [Fact]
    public void MarkCategoriesSeeded_FirstCall_SetsTimestamp()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 5, 19, 12, 0, 0, TimeSpan.Zero));
        var preference = UserPreference.CreateDefault(Guid.NewGuid(), clock);

        clock.Advance(TimeSpan.FromHours(1));
        preference.MarkCategoriesSeeded(clock);

        preference.CategoriesSeededAt.Should().Be(clock.GetUtcNow());
        preference.UpdatedAt.Should().Be(clock.GetUtcNow());
    }

    [Fact]
    public void MarkCategoriesSeeded_SecondCall_IsIdempotent()
    {
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 5, 19, 12, 0, 0, TimeSpan.Zero));
        var preference = UserPreference.CreateDefault(Guid.NewGuid(), clock);
        preference.MarkCategoriesSeeded(clock);
        DateTimeOffset firstSeededAt = preference.CategoriesSeededAt!.Value;

        clock.Advance(TimeSpan.FromHours(1));
        preference.MarkCategoriesSeeded(clock);

        preference.CategoriesSeededAt.Should().Be(firstSeededAt);
        preference.UpdatedAt.Should().Be(firstSeededAt);
    }
}
