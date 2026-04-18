namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid? ProfileId = null,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);
