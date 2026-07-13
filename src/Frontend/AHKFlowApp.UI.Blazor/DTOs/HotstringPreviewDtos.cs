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
    string? ContextValue = null);

public sealed record HotstringPreviewDto(string Snippet, RawSummaryDto? RawSummary = null);

/// <summary>Server-derived trigger and option tokens for a Raw definition; null for other kinds.</summary>
public sealed record RawSummaryDto(string Trigger, string[] OptionTokens);
