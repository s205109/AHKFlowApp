namespace AHKFlowApp.Application.DTOs;

public sealed record CategoryDto(
    Guid Id,
    string Name,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
