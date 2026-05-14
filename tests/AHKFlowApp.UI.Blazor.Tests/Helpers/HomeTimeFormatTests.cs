using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class HomeTimeFormatTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-05-13T12:00:00Z");

    [Theory]
    [InlineData(-30, "just now")]
    [InlineData(-59, "just now")]
    public void Relative_under_one_minute_returns_just_now(int seconds, string expected) =>
        HomeTimeFormat.Relative(Now, Now.AddSeconds(seconds)).Should().Be(expected);

    [Theory]
    [InlineData(-2, "2 min ago")]
    [InlineData(-14, "14 min ago")]
    [InlineData(-59, "59 min ago")]
    public void Relative_under_one_hour_returns_minutes(int minutes, string expected) =>
        HomeTimeFormat.Relative(Now, Now.AddMinutes(minutes)).Should().Be(expected);

    [Theory]
    [InlineData(-1, "1 h ago")]
    [InlineData(-23, "23 h ago")]
    public void Relative_under_one_day_returns_hours(int hours, string expected) =>
        HomeTimeFormat.Relative(Now, Now.AddHours(hours)).Should().Be(expected);

    [Fact]
    public void Relative_yesterday_returns_yesterday() =>
        HomeTimeFormat.Relative(Now, Now.AddDays(-1)).Should().Be("Yesterday");

    [Fact]
    public void Relative_older_than_yesterday_returns_iso_date() =>
        HomeTimeFormat.Relative(Now, DateTimeOffset.Parse("2026-05-01T08:00:00Z"))
            .Should().Be("2026-05-01");
}
