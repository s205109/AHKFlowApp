using System.Net;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace AHKFlowApp.API.Tests.Program;

[Collection("WebApi")]
public sealed class ProgramTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task Root_RedirectsToSwagger()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient(
            new WebApplicationFactoryClientOptions
            {
                AllowAutoRedirect = false
            });

        // Act
        HttpResponseMessage response = await client.GetAsync("/");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Redirect);
        response.Headers.Location!.ToString().Should().Be("/swagger");
    }

    [Fact]
    public async Task HealthEndpoint_ReturnsPlainTextHealthy()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/health");
        string body = await response.Content.ReadAsStringAsync();

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Be("Healthy");
    }

    [Fact]
    public async Task SwaggerEndpoint_Returns200()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/swagger/index.html");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    public void Dispose() => _factory.Dispose();
}
