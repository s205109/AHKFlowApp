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
    DateOffsetUnit? DateOffsetUnit = null);

public sealed record HotstringPreviewDto(string Snippet);
