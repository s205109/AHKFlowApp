using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.API.Models;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace AHKFlowApp.API.Tests.Health;

[Collection("WebApi")]
public sealed class HealthControllerTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task GetHealth_WhenDatabaseReachable_Returns200WithHealthyStatus()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body.Should().NotBeNull();
        body!.Status.Should().Be("Healthy");
        body.Checks.Should().ContainKey("database");
        body.Checks["database"].Should().Be("Healthy");
    }

    [Fact]
    public async Task GetHealth_ReturnsExpectedShape()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body!.Environment.Should().NotBeNullOrEmpty();
        body.Version.Should().NotBeNullOrWhiteSpace();
        body.Timestamp.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromMinutes(1));
    }

    [Fact]
    public async Task GetHealth_InfrastructureEndpoint_ReturnsHealthyText()
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
    public async Task GetHealth_WhenResourceTierSet_ReturnsTierInResponse()
    {
        // Arrange
        using WebApplicationFactory<global::Program> factory = _factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?> { ["RESOURCE_TIER"] = "free" })));
        using HttpClient client = factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body!.Tier.Should().Be("free");
    }

    [Fact]
    public async Task GetHealth_WhenResourceTierAbsent_ReturnsTierNull()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body!.Tier.Should().BeNull();
    }

    public void Dispose() => _factory.Dispose();
}
