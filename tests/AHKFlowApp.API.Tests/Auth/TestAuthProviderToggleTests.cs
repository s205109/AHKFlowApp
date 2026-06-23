using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace AHKFlowApp.API.Tests.Auth;

[Collection("WebApi")]
public sealed class TestAuthProviderToggleTests(ApiTestFixture fixture)
{
    private readonly ApiTestFixture _fixture = fixture;

    [Fact]
    public async Task WhoAmI_WithToggleOn_Returns200_WithSyntheticUser()
    {
        using CustomWebApplicationFactory baseFactory = new(_fixture.SqlFixture, useHeaderTestAuth: false);
        using WebApplicationFactory<global::Program> factory = baseFactory.WithWebHostBuilder(b =>
        {
            b.UseSetting("Auth:UseTestProvider", "true");
        });
        using HttpClient client = factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        string body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("local@homelab.invalid");
    }
}
