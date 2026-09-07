using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.TestUtilities.Tests.Fixtures;

/// <summary>
/// Guards the fixture name as a test id. Two theories now pass a name instead of the fixture
/// itself, and look the fixture back up by that name, so a duplicate name would silently make two
/// cases share one id — exactly the collapse the change removed. Most names are generated from the
/// key registry, so the set grows whenever a key spelling is added.
/// </summary>
public sealed class LegacyHotkeyFixturesTests
{
    [Fact]
    public void AllNames_AreUnique()
    {
        // Ordinal, not case-insensitive. Names that differ only by case are deliberate here:
        // {vk1} against {VK1}, and {sc01B} against {SC01B}. xUnit builds the id from the exact
        // display name, so those stay two ids.
        LegacyHotkeyFixtures.AllNames.Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void AllNames_AreUsableAsTestIds()
    {
        LegacyHotkeyFixtures.AllNames.Should().OnlyContain(
            name => !string.IsNullOrWhiteSpace(name) && !name.Any(char.IsControl),
            "a blank or control-character name cannot round-trip through a TRX or a test filter");
    }

    [Fact]
    public void AllNames_CoversEveryFixture()
    {
        LegacyHotkeyFixtures.AllNames.Should().HaveCount(LegacyHotkeyFixtures.All.Count);
    }

    [Fact]
    public void ByName_ReturnsTheFixtureThatCarriesTheName()
    {
        foreach (LegacyHotkeyFixture expected in LegacyHotkeyFixtures.All)
            LegacyHotkeyFixtures.ByName(expected.Name).Should().BeSameAs(expected);
    }
}
