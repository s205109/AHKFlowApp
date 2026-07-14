namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotstringDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Trigger,
    string Replacement,
    string? Description,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[]? CategoryIds = null,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null,
    HotstringDelivery Delivery = HotstringDelivery.Auto,
    bool ReplacementIsTruncated = false);
