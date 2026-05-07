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
}
