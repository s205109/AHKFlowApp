using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace AHKFlowApp.API.Tests.Auth;

[Collection("WebApi")]
public sealed class TestAuthProviderToggleTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _base = new(sqlFixture);

    [Fact]
    public async Task WhoAmI_WithToggleOn_Returns200_WithSyntheticUser()
    {
        using WebApplicationFactory<global::Program> factory = _base.WithWebHostBuilder(b =>
        {
            b.UseSetting("Auth:UseTestProvider", "true");
        });
        using HttpClient client = factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/whoami");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        string body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("local@homelab.invalid");
    }

    public void Dispose() => _base.Dispose();
}
