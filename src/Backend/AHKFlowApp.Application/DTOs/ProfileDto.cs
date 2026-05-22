namespace AHKFlowApp.Application.DTOs;

/// <summary>A named grouping of hotstrings and hotkeys.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="Name">User-chosen profile name.</param>
/// <param name="IsDefault">True for the user's single default profile.</param>
/// <param name="HeaderTemplate">Liquid-style header injected at the top of the generated <c>.ahk</c> script.</param>
/// <param name="FooterTemplate">Liquid-style footer appended to the generated <c>.ahk</c> script.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
public sealed record ProfileDto(
    Guid Id,
    string Name,
    bool IsDefault,
    string HeaderTemplate,
    string FooterTemplate,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload to create a new profile.</summary>
/// <param name="Name">Profile name. Must be unique per user.</param>
/// <param name="HeaderTemplate">Optional header template; falls back to the application default.</param>
/// <param name="FooterTemplate">Optional footer template; falls back to the application default.</param>
/// <param name="IsDefault">When true, marks this profile as the user's default and clears the flag on any other.</param>
public sealed record CreateProfileDto(
    string Name,
    string? HeaderTemplate = null,
    string? FooterTemplate = null,
    bool IsDefault = false);

/// <summary>Payload to replace the editable fields of an existing profile.</summary>
/// <param name="Name">Profile name. Must be unique per user.</param>
/// <param name="HeaderTemplate">Header template content.</param>
/// <param name="FooterTemplate">Footer template content.</param>
/// <param name="IsDefault">When true, marks this profile as the user's default.</param>
public sealed record UpdateProfileDto(
    string Name,
    string HeaderTemplate,
    string FooterTemplate,
    bool IsDefault);
