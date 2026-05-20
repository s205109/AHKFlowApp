namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CategoryDto(
    Guid Id,
    string Name,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
