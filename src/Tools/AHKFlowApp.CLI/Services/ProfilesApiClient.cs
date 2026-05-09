using System.Net.Http.Json;
using System.Text.Json;

namespace AHKFlowApp.CLI.Services;

public sealed class ProfilesApiClient(HttpClient http) : IProfilesApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = JsonSerializerOptions.Web;

    public async Task<IReadOnlyList<ProfileSummary>> ListAsync(CancellationToken ct)
    {
        using HttpResponseMessage response = await http.GetAsync("api/v1/profiles", ct);
        if (!response.IsSuccessStatusCode)
        {
            string body = await response.Content.ReadAsStringAsync(ct);
            throw new ApiException((int)response.StatusCode, body);
        }
        IReadOnlyList<ProfileItem>? items = await response.Content
            .ReadFromJsonAsync<IReadOnlyList<ProfileItem>>(JsonOptions, ct);
        if (items is null)
            throw new InvalidOperationException("API returned empty body for list profiles.");
        return items.Select(p => new ProfileSummary(p.Id, p.Name)).ToList();
    }

    private sealed record ProfileItem(Guid Id, string Name);
}
