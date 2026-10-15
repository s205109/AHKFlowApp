using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class ChangelogTextTests
{
    [Fact]
    public void Split_plain_text_returns_single_text_piece() =>
        ChangelogText.Split("In-app changelog page.").Should().Equal(
            new ChangelogTextPiece.Text("In-app changelog page."));

    [Fact]
    public void Split_empty_text_returns_no_pieces() =>
        ChangelogText.Split("").Should().BeEmpty();

    [Fact]
    public void Split_code_span_returns_code_piece_without_backticks() =>
        ChangelogText.Split("Run `ahkflow hotstring list` now.").Should().Equal(
            new ChangelogTextPiece.Text("Run "),
            new ChangelogTextPiece.Code("ahkflow hotstring list"),
            new ChangelogTextPiece.Text(" now."));

    [Fact]
    public void Split_strong_span_returns_strong_piece_without_asterisks() =>
        ChangelogText.Split("Turn on **Trigger inside words** first.").Should().Equal(
            new ChangelogTextPiece.Text("Turn on "),
            new ChangelogTextPiece.Strong("Trigger inside words"),
            new ChangelogTextPiece.Text(" first."));

    [Fact]
    public void Split_spans_at_both_ends_return_no_empty_text_pieces() =>
        ChangelogText.Split("`T` and **bold**").Should().Equal(
            new ChangelogTextPiece.Code("T"),
            new ChangelogTextPiece.Text(" and "),
            new ChangelogTextPiece.Strong("bold"));

    [Fact]
    public void Split_entry_that_is_one_code_span_returns_one_code_piece() =>
        ChangelogText.Split("`--inside-word`").Should().Equal(
            new ChangelogTextPiece.Code("--inside-word"));

    [Fact]
    public void Split_several_code_spans_returns_each_one() =>
        ChangelogText.Split("`--delivery auto|hotstring|clipboard` (`type` is an alias)").Should().Equal(
            new ChangelogTextPiece.Code("--delivery auto|hotstring|clipboard"),
            new ChangelogTextPiece.Text(" ("),
            new ChangelogTextPiece.Code("type"),
            new ChangelogTextPiece.Text(" is an alias)"));

    [Theory]
    [InlineData("A lone ` backtick")]
    [InlineData("A lone ** marker")]
    [InlineData("Empty `` code")]
    [InlineData("Empty **** strong")]
    [InlineData("Three *** stars")]
    [InlineData("One *star* only")]
    public void Split_marker_without_partner_stays_in_text(string text) =>
        ChangelogText.Split(text).Should().Equal(new ChangelogTextPiece.Text(text));

    // Plan review round 1: the first scan moved one character past a rejected run, so the run's
    // last marker opened a span with the next valid marker and swallowed the text between.
    [Fact]
    public void Split_empty_backtick_run_stays_text_and_a_later_code_span_still_renders() =>
        ChangelogText.Split("Empty `` then `x`").Should().Equal(
            new ChangelogTextPiece.Text("Empty `` then "),
            new ChangelogTextPiece.Code("x"));

    [Fact]
    public void Split_empty_strong_run_stays_text_and_a_later_strong_span_still_renders() =>
        ChangelogText.Split("Empty **** then **x**").Should().Equal(
            new ChangelogTextPiece.Text("Empty **** then "),
            new ChangelogTextPiece.Strong("x"));

    [Fact]
    public void Split_double_backtick_inside_code_span_stays_code() =>
        ChangelogText.Split("`a``b`").Should().Equal(
            new ChangelogTextPiece.Code("a``b"));

    [Fact]
    public void Split_strong_marker_inside_code_span_stays_code() =>
        ChangelogText.Split("Use `a**b` here").Should().Equal(
            new ChangelogTextPiece.Text("Use "),
            new ChangelogTextPiece.Code("a**b"),
            new ChangelogTextPiece.Text(" here"));

    // A strong piece holds plain text, so a code span inside it is not parsed. The real changelog's
    // format rules this out, and ChangelogFlowTests names any entry that breaks the format.
    [Fact]
    public void Split_backticks_inside_strong_span_stay_text() =>
        ChangelogText.Split("**see `x`**").Should().Equal(
            new ChangelogTextPiece.Strong("see `x`"));

    [Fact]
    public void Split_markup_characters_stay_in_the_pieces_unchanged() =>
        ChangelogText.Split("<b>a</b> `<i>`").Should().Equal(
            new ChangelogTextPiece.Text("<b>a</b> "),
            new ChangelogTextPiece.Code("<i>"));
}
