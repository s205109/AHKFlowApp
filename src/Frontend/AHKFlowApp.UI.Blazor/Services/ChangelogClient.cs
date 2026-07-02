using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class ChangelogClient(HttpClient httpClient) : ApiClientBase(httpClient), IChangelogClient
{
    private const string Path = "changelog.json";

    public Task<ApiResult<ChangelogDocumentDto>> GetAsync(CancellationToken ct = default) =>
        SendAsync<ChangelogDocumentDto>(HttpMethod.Get, Path, content: null, ct);
}
