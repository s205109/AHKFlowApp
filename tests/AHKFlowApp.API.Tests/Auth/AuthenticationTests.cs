using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Auth;

[Collection("WebApi")]
public sealed class AuthenticationTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task GetWhoAmI_WithoutToken_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GetWhoAmI_WithTestUser_Returns200AndClaims()
    {
        var oid = Guid.NewGuid();
        using HttpClient client = _factory.CreateAuthenticatedClient(u => u.WithOid(oid).WithEmail("bart@example.com"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        string body = await response.Content.ReadAsStringAsync();
        body.Should().Contain(oid.ToString());
        body.Should().Contain("bart@example.com");
    }

    [Fact]
    public async Task GetWhoAmI_WithMissingScope_Returns403()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(u => u.WithoutScope());

        HttpResponseMessage response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task GetHealth_Anonymous_StillWorks()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/health");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
