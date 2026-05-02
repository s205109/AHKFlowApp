namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record ProfileDto(
    Guid Id,
    string Name,
    bool IsDefault,
    string HeaderTemplate,
    string FooterTemplate,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record CreateProfileDto(
    string Name,
    string? HeaderTemplate = null,
    string? FooterTemplate = null,
    bool IsDefault = false);

public sealed record UpdateProfileDto(
    string Name,
    string HeaderTemplate,
    string FooterTemplate,
    bool IsDefault);
