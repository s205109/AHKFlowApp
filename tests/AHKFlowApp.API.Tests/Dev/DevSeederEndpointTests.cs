using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Dev;

[Collection("WebApi")]
public sealed class DevSeederEndpointTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task Seed_InDevelopment_Returns200WithSeededItems()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        HttpResponseMessage response = await client.PostAsync("/api/v1/dev/hotstrings/seed?reset=true", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        body!.Items.Count.Should().BeGreaterThanOrEqualTo(3);
    }
}
