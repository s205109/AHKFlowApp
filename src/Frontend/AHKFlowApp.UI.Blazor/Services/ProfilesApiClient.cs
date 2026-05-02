using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class ProfilesApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IProfilesApiClient
{
    private const string BasePath = "api/v1/profiles";

    public Task<ApiResult<IReadOnlyList<ProfileDto>>> ListAsync(CancellationToken ct = default) =>
        SendAsync<IReadOnlyList<ProfileDto>>(HttpMethod.Get, BasePath, content: null, ct);

    public Task<ApiResult<ProfileDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<ProfileDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<ProfileDto>> CreateAsync(CreateProfileDto input, CancellationToken ct = default) =>
        SendAsync<ProfileDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<ProfileDto>> UpdateAsync(Guid id, UpdateProfileDto input, CancellationToken ct = default) =>
        SendAsync<ProfileDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);
}
