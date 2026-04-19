namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotstringDto(
    Guid Id,
    Guid? ProfileId,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
