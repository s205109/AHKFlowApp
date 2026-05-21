namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string? Description,
    Guid[]? CategoryIds = null);
