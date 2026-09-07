using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class LegacyHotkeyDefinitionConverterTests
{
    // Takes the fixture's name, not the fixture. A record does not serialize, so xUnit could not
    // write it into the test id and all 340 cases reported under one id — one Test Explorer row,
    // no way to re-run a single case. A string serializes, so each case gets its own id.
    [Theory]
    [MemberData(nameof(Cases))]
    public void ToTyped_LegacyPair_MatchesFixtureExpectation(string fixtureName)
    {
        LegacyHotkeyFixture f = LegacyHotkeyFixtures.ByName(fixtureName);

        LegacyHotkeyDefinitionConverter.TypedAction typed =
            LegacyHotkeyDefinitionConverter.ToTyped(f.Action, f.Parameters);

        typed.ActionKind.Should().Be(f.ExpectedKind, "fixture '{0}'", f.Name);
        typed.Text.Should().Be(f.ExpectedText, "fixture '{0}'", f.Name);
        typed.SendKeysContent.Should().Be(f.ExpectedSendKeysContent, "fixture '{0}'", f.Name);
        typed.RunTarget.Should().Be(f.ExpectedRunTarget, "fixture '{0}'", f.Name);
        typed.RunTargetKind.Should().Be(f.ExpectedRunTargetKind, "fixture '{0}'", f.Name);
        typed.Body.Should().Be(f.ExpectedBody, "fixture '{0}'", f.Name);
    }

    public static TheoryData<string> Cases() => new(LegacyHotkeyFixtures.AllNames);

    // The other half of the divergence ADR 0004 records. The live converter resolves LControl
    // through the alias map, so a legacy history snapshot restores as SendKeys where the migrated
    // row stays Raw. Both halves are pinned, so neither side can move unnoticed.
    [Fact]
    public void ToTyped_SpellingAddedAfterMigrationA_IsSendKeys()
    {
        LegacyHotkeyDefinitionConverter.TypedAction typed = LegacyHotkeyDefinitionConverter.ToTyped(
            LegacyHotkeyDefinitionConverter.HotkeyAction.Send, "{LControl}");

        typed.ActionKind.Should().Be(HotkeyActionKind.SendKeys);
        typed.SendKeysContent.Should().Be("{LControl}");
        typed.Body.Should().BeNull();
    }
}
