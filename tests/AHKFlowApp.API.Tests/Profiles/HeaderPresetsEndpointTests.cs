using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Profiles;

[Collection("WebApi")]
public sealed class HeaderPresetsEndpointTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task GetHeaderPresets_ReturnsTheShippedList()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/profiles/header-presets");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HeaderPresetCatalogDto? catalog =
            await response.Content.ReadFromJsonAsync<HeaderPresetCatalogDto>();
        catalog.Should().NotBeNull();
        catalog!.Presets.Should().NotBeEmpty();
        catalog.Presets.Should().AllSatisfy(p =>
        {
            p.Id.Should().NotBeNullOrWhiteSpace();
            p.Body.Should().NotBeNullOrWhiteSpace();
            p.Tag.Should().NotBeNullOrWhiteSpace();
        });
    }

    [Fact]
    public async Task GetHeaderPresets_WithoutAuth_IsRejected()
    {
        HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/profiles/header-presets");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
