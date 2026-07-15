namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotstringPreviewRequestDto(
    HotstringKind Kind,
    string Trigger,
    string Replacement,
    bool IsCaseSensitive,
    bool OmitEndingCharacter,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null,
    string? Description = null,
    HotstringDelivery Delivery = HotstringDelivery.Auto);

public sealed record HotstringPreviewDto(
    string Snippet,
    RawSummaryDto? RawSummary = null,
    HotstringDelivery EffectiveDelivery = HotstringDelivery.Type);

/// <summary>Body shape of a Raw hotstring definition (mirror of the backend enum).</summary>
public enum RawBodyKind
{
    None,
    Inline,
    Braces,
    Continuation,
}

/// <summary>Server-derived summary of a Raw definition; null for other kinds.</summary>
public sealed record RawSummaryDto(
    string Trigger,
    string[] OptionTokens,
    RawBodyKind BodyKind,
    int BodyLineCount,
    string? LiftedComment);
