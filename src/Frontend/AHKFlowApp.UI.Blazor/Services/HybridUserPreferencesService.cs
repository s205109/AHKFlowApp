using AHKFlowApp.UI.Blazor.DTOs;
using Microsoft.AspNetCore.Components.Authorization;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HybridUserPreferencesService : IUserPreferencesService, IDisposable
{
    private readonly AuthenticationStateProvider _authStateProvider;
    private readonly IPreferencesApiClient _preferencesApi;
    private readonly LocalStorageUserPreferencesService _localStorage;

    public HybridUserPreferencesService(
        AuthenticationStateProvider authStateProvider,
        IPreferencesApiClient preferencesApi,
        LocalStorageUserPreferencesService localStorage)
    {
        _authStateProvider = authStateProvider;
        _preferencesApi = preferencesApi;
        _localStorage = localStorage;
        authStateProvider.AuthenticationStateChanged += OnAuthStateChangedAsync;
    }

    public event Action<UserPreferences>? OnChange;
    private UserPreferences? _cache;

    public async ValueTask<UserPreferences> GetAsync(CancellationToken ct = default)
    {
        if (_cache is not null)
            return _cache;

        AuthenticationState authState = await _authStateProvider.GetAuthenticationStateAsync();

        if (authState.User.Identity?.IsAuthenticated is true)
        {
            ApiResult<UserPreferenceDto> result = await _preferencesApi.GetAsync(ct);
            if (result.IsSuccess && result.Value is { } dto)
            {
                UserPreferences serverPrefs = new(dto.RowsPerPage, dto.DarkMode);
                await _localStorage.SetAsync(serverPrefs, ct);
                _cache = serverPrefs;
                return serverPrefs;
            }
            // 404 (no server record yet) and any other failure both fall through to local storage.
        }

        UserPreferences localPrefs = await _localStorage.GetAsync(ct);
        _cache = localPrefs;
        return localPrefs;
    }

    public async ValueTask SetAsync(UserPreferences preferences, CancellationToken ct = default)
    {
        bool changed = _cache != preferences;
        _cache = preferences;
        if (changed)
            OnChange?.Invoke(preferences);

        await _localStorage.SetAsync(preferences, ct);

        AuthenticationState authState = await _authStateProvider.GetAuthenticationStateAsync();
        if (authState.User.Identity?.IsAuthenticated is true)
        {
            await _preferencesApi.UpdateAsync(
                new UpdateUserPreferenceDto(preferences.RowsPerPage, preferences.DarkMode), ct);
        }
    }

    public void Dispose() =>
        _authStateProvider.AuthenticationStateChanged -= OnAuthStateChangedAsync;

    private async void OnAuthStateChangedAsync(Task<AuthenticationState> task)
    {
        try
        {
            AuthenticationState authState = await task;
            if (authState.User.Identity?.IsAuthenticated is not true)
                return;

            _cache = null;
            ApiResult<UserPreferenceDto> result = await _preferencesApi.GetAsync();
            if (result.IsSuccess && result.Value is { } dto)
            {
                UserPreferences serverPrefs = new(dto.RowsPerPage, dto.DarkMode);
                await _localStorage.SetAsync(serverPrefs);
                _cache = serverPrefs;
                OnChange?.Invoke(serverPrefs);
            }
        }
        catch
        {
            // Best-effort: leave existing preferences in place on transient failure.
        }
    }
}
