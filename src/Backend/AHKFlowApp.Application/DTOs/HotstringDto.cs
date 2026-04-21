namespace AHKFlowApp.Application.DTOs;

public sealed record HotstringDto(
    Guid Id,
    Guid? ProfileId,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid? ProfileId = null,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true);

public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid? ProfileId,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord);
