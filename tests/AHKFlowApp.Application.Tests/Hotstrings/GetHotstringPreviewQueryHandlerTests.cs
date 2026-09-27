using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class GetHotstringPreviewQueryHandlerTests
{
    private readonly GetHotstringPreviewQueryHandler _sut = new(TimeProvider.System);

    private static GetHotstringPreviewQuery Query(
        HotstringKind kind, string replacement, string? description = null, string trigger = "btw")
        => new(new HotstringPreviewRequestDto(
            kind, trigger, replacement,
            IsCaseSensitive: false, OmitEndingCharacter: false,
            IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
            Description: description));

    [Fact]
    public async Task Preview_NonRawWithDescription_PrependsCommentToSnippet()
    {
        Result<HotstringPreviewDto> result = await _sut.ExecuteAsync(
            Query(HotstringKind.Text, "by the way", description: "a note"), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Snippet.Should().Be("; a note\n:T:btw::by the way");
    }

    [Fact]
    public async Task Preview_RawContinuation_SummaryCarriesBodyKindAndLineCount()
    {
        Result<HotstringPreviewDto> result = await _sut.ExecuteAsync(
            Query(HotstringKind.Raw, ":*:col::\n(\nred\ngreen\nblue\n)"), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.RawSummary!.BodyKind.Should().Be(RawBodyKind.Continuation);
        result.Value.RawSummary.BodyLineCount.Should().Be(3);
        result.Value.RawSummary.LiftedComment.Should().BeNull();
    }

    [Fact]
    public async Task Preview_RawWithLeadingComment_LiftsIntoSummaryAndSnippet()
    {
        Result<HotstringPreviewDto> result = await _sut.ExecuteAsync(
            Query(HotstringKind.Raw, "; moved note\n::btw::by the way"), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.RawSummary!.LiftedComment.Should().Be("moved note");
        result.Value.Snippet.Should().Be("; moved note\n::btw::by the way");
    }

    // Pins the order of a full preview: the Runtime helper first, then the #HotIf block, with the
    // Description comment inside it, above the definition. The helper text itself comes from its
    // constant, so this test pins the order and not the helper's bytes.
    [Fact]
    public async Task Preview_ClipboardWithWindowContextAndDescription_PutsHelperAboveHotIfBlock()
    {
        Result<HotstringPreviewDto> result = await _sut.ExecuteAsync(
            new GetHotstringPreviewQuery(new HotstringPreviewRequestDto(
                HotstringKind.Text, "sig", "Best regards",
                IsCaseSensitive: false, OmitEndingCharacter: false,
                IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
                ContextMatchType: WindowMatchType.WindowClass, ContextValue: "Notepad",
                Description: "a note", Delivery: HotstringDelivery.ClipboardPaste)),
            default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Snippet.Should().Be(
            RuntimeHelpers.ClipboardPasteFunction + "\n" +
            "#HotIf WinActive(\"ahk_class Notepad\")\n" +
            "; a note\n" +
            ":X:sig::AhkFlow_PasteReplacement(\"Best regards\", A_EndChar)\n" +
            "#HotIf");
    }
}
