namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);
