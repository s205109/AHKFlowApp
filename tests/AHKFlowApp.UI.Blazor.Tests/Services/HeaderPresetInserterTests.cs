using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HeaderPresetInserterTests
{
    private static HeaderPresetDto Preset(string body = "SetNumLockState \"AlwaysOff\"") =>
        new("lock-keys-off", "Keep lock keys off", "Holds three keys off.", "Lock keys", body);

    [Fact]
    public void Insert_IntoEmptyHeader_WritesBlockWithNoLeadingBlankLine()
    {
        HeaderPresetInsertResult result = HeaderPresetInserter.Insert("", Preset());

        result.Inserted.Should().BeTrue();
        result.Header.Should().Be(
            "; --- AHKFlow preset: lock-keys-off ---\n" +
            "SetNumLockState \"AlwaysOff\"\n" +
            "; --- end lock-keys-off ---\n");
    }

    [Fact]
    public void Insert_WhenHeaderHasNoTrailingLineBreak_AddsOneFirst()
    {
        HeaderPresetInsertResult result = HeaderPresetInserter.Insert("SetTitleMatchMode 2", Preset());

        result.Header.Should().StartWith("SetTitleMatchMode 2\n\n; --- AHKFlow preset:");
    }

    [Fact]
    public void Insert_WhenHeaderEndsWithALineBreak_AddsOneBlankLineOnly()
    {
        HeaderPresetInsertResult result = HeaderPresetInserter.Insert("SetTitleMatchMode 2\n", Preset());

        result.Header.Should().StartWith("SetTitleMatchMode 2\n\n; --- AHKFlow preset:");
    }

    [Fact]
    public void Insert_WhenHeaderEndsWithWindowsLineBreak_AddsNoExtraBreak()
    {
        HeaderPresetInsertResult result = HeaderPresetInserter.Insert("SetTitleMatchMode 2\r\n", Preset());

        result.Header.Should().StartWith("SetTitleMatchMode 2\r\n\n; --- AHKFlow preset:");
    }

    [Fact]
    public void Insert_LeavesExactlyOneTrailingLineBreak()
    {
        HeaderPresetInsertResult first = HeaderPresetInserter.Insert("head", Preset());
        HeaderPresetInsertResult second = HeaderPresetInserter.Insert(
            first.Header, Preset() with { Id = "other-preset" });

        second.Header.Should().EndWith("; --- end other-preset ---\n");
        second.Header.Should().NotEndWith("\n\n");
    }

    [Fact]
    public void Insert_WhenResultWouldPassTheCap_RefusesAndLeavesTheHeaderAlone()
    {
        string header = new('x', HeaderPresetInserter.HeaderMaxLength - 10);

        HeaderPresetInsertResult result = HeaderPresetInserter.Insert(header, Preset());

        result.Inserted.Should().BeFalse();
        result.Header.Should().Be(header);
        result.Error.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public void Insert_WhenResultLandsExactlyOnTheCap_Inserts()
    {
        HeaderPresetDto preset = Preset("ab");
        int blockLength = HeaderPresetInserter.Insert("", preset).Header.Length;
        // header + "\n" (missing break) + "\n" (blank line) + block
        string header = new('x', HeaderPresetInserter.HeaderMaxLength - blockLength - 2);

        HeaderPresetInsertResult result = HeaderPresetInserter.Insert(header, preset);

        result.Inserted.Should().BeTrue();
        result.Header.Length.Should().Be(HeaderPresetInserter.HeaderMaxLength);
    }

    [Fact]
    public void IsPresent_IsTrueOnlyForAnIdAlreadyInTheHeader()
    {
        string header = HeaderPresetInserter.Insert("", Preset()).Header;

        HeaderPresetInserter.IsPresent(header, "lock-keys-off").Should().BeTrue();
        HeaderPresetInserter.IsPresent(header, "capslock-modifier-layer").Should().BeFalse();
    }
}
