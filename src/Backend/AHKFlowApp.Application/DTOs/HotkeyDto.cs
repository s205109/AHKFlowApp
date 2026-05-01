namespace AHKFlowApp.Application.DTOs;

public sealed record HotkeyDto(
    Guid Id,
    Guid? ProfileId,
    string Trigger,
    string Action,
    string? Description,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record CreateHotkeyDto(
    string Trigger,
    string Action,
    string? Description = null,
    Guid? ProfileId = null);

public sealed record UpdateHotkeyDto(
    string Trigger,
    string Action,
    string? Description,
    Guid? ProfileId);
