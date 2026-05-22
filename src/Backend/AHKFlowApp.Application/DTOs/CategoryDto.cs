namespace AHKFlowApp.Application.DTOs;

/// <summary>A user-defined category for grouping hotstrings and hotkeys.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="Name">User-chosen category name.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
public sealed record CategoryDto(
    Guid Id,
    string Name,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
