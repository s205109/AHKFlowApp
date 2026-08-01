using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class GreetingTests
{
    [Fact]
    public void Build_AtElevenFiftyNine_IsMorning() =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, 11, 59, 0, TimeSpan.Zero), "Test User")
            .Should().Be("Good morning, Test User");

    [Fact]
    public void Build_AtNoon_IsAfternoon() =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, 12, 0, 0, TimeSpan.Zero), "Test User")
            .Should().Be("Good afternoon, Test User");

    [Fact]
    public void Build_AtSeventeenFiftyNine_IsAfternoon() =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, 17, 59, 0, TimeSpan.Zero), "Test User")
            .Should().Be("Good afternoon, Test User");

    [Fact]
    public void Build_AtEighteen_IsEvening() =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, 18, 0, 0, TimeSpan.Zero), "Test User")
            .Should().Be("Good evening, Test User");

    [Theory]
    [InlineData(0)]
    [InlineData(6)]
    public void Build_EarlyMorningHours_AreMorning(int hour) =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, hour, 0, 0, TimeSpan.Zero), "Test User")
            .Should().Be("Good morning, Test User");

    [Theory]
    [InlineData(19)]
    [InlineData(23)]
    public void Build_LateHours_AreEvening(int hour) =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, hour, 0, 0, TimeSpan.Zero), "Test User")
            .Should().Be("Good evening, Test User");

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Build_WhenNameIsMissing_ReturnsNull(string? name) =>
        Greeting.Build(new DateTimeOffset(2026, 8, 1, 9, 0, 0, TimeSpan.Zero), name)
            .Should().BeNull();

    [Fact]
    public void Build_WithTimeProvider_ReadsTheClockInLocalTime()
    {
        // 10:00 UTC + 9h local offset = 19:00 local -> evening
        FakeTimeProvider clock = new(new DateTimeOffset(2026, 8, 1, 10, 0, 0, TimeSpan.Zero));
        clock.SetLocalTimeZone(TimeZoneInfo.CreateCustomTimeZone("t", TimeSpan.FromHours(9), "t", "t"));

        Greeting.Build(clock, "Test User").Should().Be("Good evening, Test User");
    }
}
