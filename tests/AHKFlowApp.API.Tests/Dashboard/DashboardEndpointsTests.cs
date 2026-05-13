using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Dashboard;

[Collection("WebApi")]
public sealed class DashboardEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

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
    public async Task GET_stats_returns_401_for_unauthenticated_request()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/dashboard/stats");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    public void Dispose() => _factory.Dispose();
}
