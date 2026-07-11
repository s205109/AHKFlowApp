using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class MacroTokensTests
{
    [Theory]
    [InlineData("Dear customer")]
    [InlineData("")]
    [InlineData("{{ cursor }}")]
    [InlineData("{{key:enter }}")]
    public void ContainsKnownToken_no_real_token_returns_false(string text) =>
        MacroTokens.ContainsKnownToken(text).Should().BeFalse();

    [Theory]
    [InlineData("{{cursor}}")]
    [InlineData("{{CURSOR}}")]
    [InlineData("{{key:Enter}}")]
    [InlineData("{{KEY:ENTER}}")]
    [InlineData("{{key:enter}}")]
    [InlineData("{{key:Tab}}")]
    [InlineData("{{KEY:TAB}}")]
    [InlineData("Dear {{cursor}} name")]
    public void ContainsKnownToken_real_token_returns_true(string text) =>
        MacroTokens.ContainsKnownToken(text).Should().BeTrue();

    [Fact]
    public void ContainsKnownToken_escaped_literal_alone_returns_false() =>
        MacroTokens.ContainsKnownToken("{{{{cursor}}}}").Should().BeFalse();

    [Fact]
    public void ContainsKnownToken_escaped_literal_alongside_real_token_returns_true() =>
        MacroTokens.ContainsKnownToken("{{{{cursor}}}}{{key:Enter}}").Should().BeTrue();

    [Fact]
    public void Split_plain_text_returns_single_text_piece()
    {
        IReadOnlyList<MacroTextPiece> pieces = MacroTokens.Split("Dear customer");

        pieces.Should().ContainSingle().Which.Should().BeOfType<MacroTextPiece.Text>()
            .Which.Value.Should().Be("Dear customer");
    }

    [Fact]
    public void Split_real_token_returns_alternating_pieces()
    {
        IReadOnlyList<MacroTextPiece> pieces = MacroTokens.Split("Dear {{cursor}}Alex");

        pieces.Should().HaveCount(3);
        pieces[0].Should().BeOfType<MacroTextPiece.Text>().Which.Value.Should().Be("Dear ");
        pieces[1].Should().BeOfType<MacroTextPiece.Token>().Which.Kind.Should().Be(MacroTokenKind.Cursor);
        pieces[2].Should().BeOfType<MacroTextPiece.Text>().Which.Value.Should().Be("Alex");
    }

    [Fact]
    public void Split_escaped_literal_returns_single_unescaped_text_piece()
    {
        IReadOnlyList<MacroTextPiece> pieces = MacroTokens.Split("{{{{first_name}}}}");

        pieces.Should().ContainSingle().Which.Should().BeOfType<MacroTextPiece.Text>()
            .Which.Value.Should().Be("{{first_name}}");
    }

    [Fact]
    public void Split_mixed_example_produces_expected_piece_sequence()
    {
        IReadOnlyList<MacroTextPiece> pieces =
            MacroTokens.Split("Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex");

        pieces.Should().HaveCount(4);
        pieces[0].Should().BeOfType<MacroTextPiece.Text>().Which.Value.Should().Be("Dear {{first_name}},");
        pieces[1].Should().BeOfType<MacroTextPiece.Token>().Which.Kind.Should().Be(MacroTokenKind.Enter);
        pieces[2].Should().BeOfType<MacroTextPiece.Token>().Which.Kind.Should().Be(MacroTokenKind.Cursor);
        pieces[3].Should().BeOfType<MacroTextPiece.Text>().Which.Value.Should().Be("Alex");
    }

    [Theory]
    [InlineData("")]
    [InlineData("Dear customer")]
    [InlineData("{{key:Enter}}")]
    [InlineData("{{key:Tab}}")]
    [InlineData("{{oops}}")]
    [InlineData("{{ cursor }}")]
    public void CursorTokenStart_no_real_cursor_token_returns_null(string text) =>
        MacroTokens.CursorTokenStart(text).Should().BeNull();

    [Theory]
    [InlineData("{{cursor}}", 0)]
    [InlineData("{{CURSOR}}", 0)]
    [InlineData("{{Cursor}}", 0)]
    [InlineData("abc{{cursor}}", 3)]
    [InlineData("Dear {{cursor}} name", 5)]
    public void CursorTokenStart_real_cursor_token_returns_start_index(string text, int expectedStart) =>
        MacroTokens.CursorTokenStart(text).Should().Be(expectedStart);

    [Fact]
    public void CursorTokenStart_escaped_cursor_literal_returns_null() =>
        MacroTokens.CursorTokenStart("{{{{cursor}}}}").Should().BeNull();

    [Fact]
    public void CursorTokenStart_orphan_escape_without_closer_returns_nested_cursor_position() =>
        MacroTokens.CursorTokenStart("{{{{cursor}}").Should().Be(2);
}
