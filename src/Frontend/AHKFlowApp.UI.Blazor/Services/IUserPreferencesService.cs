namespace AHKFlowApp.UI.Blazor.Services;

public interface IUserPreferencesService
{
    ValueTask<UserPreferences> GetAsync(CancellationToken ct = default);
    ValueTask SetAsync(UserPreferences preferences, CancellationToken ct = default);
}
