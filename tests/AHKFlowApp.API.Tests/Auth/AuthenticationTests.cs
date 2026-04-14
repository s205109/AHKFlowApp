using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace AHKFlowApp.API.Tests.Auth;

[Collection("WebApi")]
public sealed class AuthenticationTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

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
        using WebApplicationFactory<global::Program> authFactory = _factory.WithTestAuth(u => u.WithOid(oid).WithEmail("bart@example.com"));
        using HttpClient client = authFactory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        string body = await response.Content.ReadAsStringAsync();
        body.Should().Contain(oid.ToString());
        body.Should().Contain("bart@example.com");
    }

    [Fact]
    public async Task GetWhoAmI_WithMissingScope_Returns403()
    {
        using WebApplicationFactory<global::Program> authFactory = _factory.WithTestAuth(u => u.WithoutScope());
        using HttpClient client = authFactory.CreateClient();

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

    public void Dispose() => _factory.Dispose();
}
