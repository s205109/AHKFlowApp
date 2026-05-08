using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkFileNamingTests
{
    [Theory]
    [InlineData("Work", "Work")]
    [InlineData("work_2025", "work_2025")]
    [InlineData("dot.name", "dot.name")]
    [InlineData("dash-name", "dash-name")]
    public void ToSafeStem_AsciiSafe_ReturnedUnchanged(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Theory]
    [InlineData("Work / Home", "Work_Home")]
    [InlineData("Work\\Home", "Work_Home")]
    [InlineData("a:b", "a_b")]
    [InlineData("a*b?c", "a_b_c")]
    [InlineData("a..b", "a..b")]
    [InlineData("naïve", "na_ve")]
    public void ToSafeStem_UnsafeChars_ReplacedWithUnderscore(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Theory]
    [InlineData("a___b", "a_b")]
    [InlineData("a   b", "a_b")]
    [InlineData("a/\\b", "a_b")]
    public void ToSafeStem_RunsOfUnderscore_CollapsedToOne(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Theory]
    [InlineData("__work__", "work")]
    [InlineData(" work ", "work")]
    [InlineData("///work", "work")]
    public void ToSafeStem_LeadingTrailingUnderscore_Trimmed(string input, string expected) =>
        AhkFileNaming.ToSafeStem(input).Should().Be(expected);

    [Fact]
    public void ToSafeStem_EmptyResult_ReturnsProfileFallback() =>
        AhkFileNaming.ToSafeStem("???").Should().Be("profile");

    [Fact]
    public void ToSafeStem_Empty_ReturnsProfileFallback() =>
        AhkFileNaming.ToSafeStem("").Should().Be("profile");

    [Fact]
    public void ToSafeStem_LongerThan64Chars_TruncatedTo64()
    {
        string input = new string('a', 100);

        string output = AhkFileNaming.ToSafeStem(input);

        output.Length.Should().Be(64);
        output.Should().Be(new string('a', 64));
    }

    [Fact]
    public void FileName_FormatsAsAhkflowPrefixWithExtension() =>
        AhkFileNaming.FileName("Work").Should().Be("ahkflow_Work.ahk");

    [Fact]
    public void FileName_AppliesSanitization() =>
        AhkFileNaming.FileName("Work / Home").Should().Be("ahkflow_Work_Home.ahk");
}
