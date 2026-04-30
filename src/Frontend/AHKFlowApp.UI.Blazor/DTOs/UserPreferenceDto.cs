namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record UserPreferenceDto(int RowsPerPage, bool DarkMode);

public sealed record UpdateUserPreferenceDto(int RowsPerPage, bool DarkMode);
