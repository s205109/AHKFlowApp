using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class CountWordingTests
{
    // Backlog 169: counts read "1 hotstring(s)". Only one takes the singular; zero takes the
    // plural, and an irregular plural such as "categories" comes from the caller.
    [Theory]
    [InlineData(0, "hotstring", "hotstrings", "0 hotstrings")]
    [InlineData(1, "hotstring", "hotstrings", "1 hotstring")]
    [InlineData(1, "category", "categories", "1 category")]
    [InlineData(2, "category", "categories", "2 categories")]
    public void Of_UsesTheSingularOnlyForOne(int count, string singular, string plural, string expected) =>
        CountWording.Of(count, singular, plural).Should().Be(expected);
}
