using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.API.Models;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Health;

[Collection("HealthApi")]
public sealed class HealthControllerTests(HealthApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task GetHealth_WhenDatabaseReachable_Returns200WithHealthyStatus()
    {
        // Act
        HttpResponseMessage response = await _client.GetAsync("/api/v1/health");

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
        // Act
        HttpResponseMessage response = await _client.GetAsync("/api/v1/health");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HealthResponse? body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        body!.Environment.Should().NotBeNullOrEmpty();
        body.Timestamp.Should().BeCloseTo(DateTimeOffset.UtcNow, TimeSpan.FromMinutes(1));
    }

    [Fact]
    public async Task GetHealth_InfrastructureEndpoint_ReturnsHealthyText()
    {
        // Act
        HttpResponseMessage response = await _client.GetAsync("/health");
        string body = await response.Content.ReadAsStringAsync();

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        body.Should().Be("Healthy");
    }
}
