using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkScriptGeneratorTests
{
    private readonly AhkScriptGenerator _sut = new();

    [Fact]
    public void Generate_EmptyProfile_EmitsHeaderSectionMarkersAndFooter()
    {
        Profile profile = new ProfileBuilder()
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("; end of file")
            .Build();

        string output = _sut.Generate(profile, [], []);

        output.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
            "; end of file");
    }

    [Fact]
    public void Generate_EmptyHeaderAndFooter_StillEmitsSectionMarkers()
    {
        Profile profile = new ProfileBuilder().WithHeader("").WithFooter("").Build();

        string output = _sut.Generate(profile, [], []);

        output.Should().Be(
            "\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n");
    }

    [Theory]
    [InlineData(true, false, "::btw::by the way")]                  // default — no options
    [InlineData(false, false, ":*:btw::by the way")]                // ending char NOT required
    [InlineData(true, true, ":?:btw::by the way")]                  // trigger inside word
    [InlineData(false, true, ":*?:btw::by the way")]                // both options
    public void Generate_Hotstring_FormatsOptionsCorrectly(
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(isEndingCharacterRequired)
            .WithTriggerInsideWord(isTriggerInsideWord)
            .Build();

        string output = _sut.Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_MultipleHotstrings_AllAppearUnderHotstringsSection()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs1 = new HotstringBuilder().WithTrigger("a").WithReplacement("alpha")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring hs2 = new HotstringBuilder().WithTrigger("b").WithReplacement("beta")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = _sut.Generate(profile, [hs1, hs2], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "::a::alpha\n" +
            "::b::beta\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }
}
