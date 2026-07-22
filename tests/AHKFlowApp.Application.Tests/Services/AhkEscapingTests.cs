using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkEscapingTests
{
    [Fact]
    public void EscapeStringLiteral_Backtick_IsEscapedFirst()
    {
        string result = AhkEscaping.EscapeStringLiteral("a`nb");

        result.Should().Be("a``nb");
    }

    [Fact]
    public void EscapeStringLiteral_DoubleQuote_IsEscaped()
    {
        string result = AhkEscaping.EscapeStringLiteral("he said \"hi\"");

        result.Should().Be("he said `\"hi`\"");
    }

    [Fact]
    public void EscapeStringLiteral_Whitespace_IsEscaped()
    {
        string result = AhkEscaping.EscapeStringLiteral("a\r\nb\tc");

        result.Should().Be("a`r`nb`tc");
    }

    [Fact]
    public void EscapeStringLiteral_PlainText_IsUnchanged()
    {
        string result = AhkEscaping.EscapeStringLiteral("notepad.exe");

        result.Should().Be("notepad.exe");
    }
}
