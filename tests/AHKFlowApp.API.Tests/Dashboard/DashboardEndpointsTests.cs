using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Dashboard;

[Collection("WebApi")]
public sealed class DashboardEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    [Fact]
    public async Task GET_stats_returns_200_with_dto_for_authenticated_user()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/dashboard/stats");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        DashboardStatsDto? dto = await response.Content.ReadFromJsonAsync<DashboardStatsDto>();
        dto.Should().NotBeNull();
        dto!.Hotstrings.DailyBuckets.Should().HaveCount(14);
        dto.Hotkeys.DailyBuckets.Should().HaveCount(14);
        dto.Profiles.DailyBuckets.Should().HaveCount(14);
    }

    [Fact]
    public async Task GET_stats_counts_the_default_profile_for_an_owner_who_never_listed_profiles()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/dashboard/stats");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        DashboardStatsDto? dto = await response.Content.ReadFromJsonAsync<DashboardStatsDto>();
        dto!.Profiles.Total.Should().Be(1);

        // The profiles page must then see the same single profile, not create a second one.
        List<ProfileDto>? profiles = await client.GetFromJsonAsync<List<ProfileDto>>("/api/v1/profiles");
        profiles.Should().ContainSingle().Which.Name.Should().Be("Default");
    }

    [Fact]
    public async Task GET_stats_returns_401_for_unauthenticated_request()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/dashboard/stats");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
