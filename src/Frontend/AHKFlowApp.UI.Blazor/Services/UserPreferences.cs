namespace AHKFlowApp.UI.Blazor.Services;

public sealed record UserPreferences(int RowsPerPage, bool DarkMode)
{
    public static UserPreferences Default { get; } = new(RowsPerPage: 10, DarkMode: false);
}
