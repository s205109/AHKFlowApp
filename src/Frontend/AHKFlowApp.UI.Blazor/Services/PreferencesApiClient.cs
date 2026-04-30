using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class PreferencesApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IPreferencesApiClient
{
    private const string BasePath = "api/v1/preferences";

    public Task<ApiResult<UserPreferenceDto>> GetAsync(CancellationToken ct = default) =>
        SendAsync<UserPreferenceDto>(HttpMethod.Get, BasePath, content: null, ct);

    public Task<ApiResult<UserPreferenceDto>> UpdateAsync(UpdateUserPreferenceDto input, CancellationToken ct = default) =>
        SendAsync<UserPreferenceDto>(HttpMethod.Put, BasePath, JsonContent.Create(input), ct);
}
