namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid? ProfileId,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord);
