using Microsoft.JSInterop;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class LocalStorageUserPreferencesService(IJSRuntime js)
{
    private const string RowsPerPageKey = "ahkflow.prefs.rowsPerPage";
    private const string DarkModeKey = "ahkflow.prefs.darkMode";

    public async ValueTask<UserPreferences> GetAsync(CancellationToken ct = default)
    {
        string? rowsRaw = await js.InvokeAsync<string?>("localStorage.getItem", ct, RowsPerPageKey);
        string? darkRaw = await js.InvokeAsync<string?>("localStorage.getItem", ct, DarkModeKey);

        int rows = int.TryParse(rowsRaw, out int parsed) ? parsed : UserPreferences.Default.RowsPerPage;
        bool dark = bool.TryParse(darkRaw, out bool parsedDark) ? parsedDark : UserPreferences.Default.DarkMode;

        return new UserPreferences(rows, dark);
    }

    public async ValueTask SetAsync(UserPreferences preferences, CancellationToken ct = default)
    {
        await js.InvokeVoidAsync("localStorage.setItem", ct, RowsPerPageKey, preferences.RowsPerPage.ToString());
        await js.InvokeVoidAsync("localStorage.setItem", ct, DarkModeKey, preferences.DarkMode.ToString());
    }
}
