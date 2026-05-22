namespace AHKFlowApp.Application.DTOs;

/// <summary>UI preferences for the current user.</summary>
/// <param name="RowsPerPage">Preferred page size in paginated tables.</param>
/// <param name="DarkMode">True when the dark theme is active.</param>
public sealed record UserPreferenceDto(int RowsPerPage, bool DarkMode);

/// <summary>Payload to update UI preferences.</summary>
/// <param name="RowsPerPage">Preferred page size in paginated tables.</param>
/// <param name="DarkMode">True when the dark theme is active.</param>
public sealed record UpdateUserPreferenceDto(int RowsPerPage, bool DarkMode);
