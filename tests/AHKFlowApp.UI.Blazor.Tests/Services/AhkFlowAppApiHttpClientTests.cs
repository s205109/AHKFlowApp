using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class AhkFlowAppApiHttpClientTests
{
    [Fact]
    public async Task GetHealthAsync_WhenApiReturnsJson_DeserializesVersionField()
    {
        // Arrange
        var expected = new HealthResponse
        {
            Status = "Healthy",
            Version = "2.0.0",
            Environment = "Production",
            Timestamp = DateTimeOffset.Parse("2026-04-04T12:00:00Z"),
            Checks = []
        };

        using HttpClient httpClient = CreateMockHttpClient(
            HttpStatusCode.OK,
            JsonContent.Create(expected));

        var client = new AhkFlowAppApiHttpClient(httpClient);

        // Act
        HealthResponse? result = await client.GetHealthAsync();

        // Assert
        result!.Version.Should().Be("2.0.0");
    }

    [Fact]
    public async Task GetHealthAsync_WhenApiReturnsJson_DeserializesResponse()
    {
        // Arrange
        var expected = new HealthResponse
        {
            Status = "Healthy",
            Environment = "Production",
            Timestamp = DateTimeOffset.Parse("2026-04-04T12:00:00Z"),
            Checks = new Dictionary<string, string> { ["database"] = "Healthy" }
        };

        using HttpClient httpClient = CreateMockHttpClient(
            HttpStatusCode.OK,
            JsonContent.Create(expected));

        var client = new AhkFlowAppApiHttpClient(httpClient);

        // Act
        HealthResponse? result = await client.GetHealthAsync();

        // Assert
        result.Should().NotBeNull();
        result!.Status.Should().Be("Healthy");
        result.Environment.Should().Be("Production");
        result.Checks.Should().ContainKey("database");
    }

    [Fact]
    public async Task GetHealthAsync_WhenApiReturns500_ThrowsHttpRequestException()
    {
        // Arrange
        using HttpClient httpClient = CreateMockHttpClient(
            HttpStatusCode.InternalServerError,
            new StringContent("Server Error"));

        var client = new AhkFlowAppApiHttpClient(httpClient);

        // Act
        Func<Task> act = async () => await client.GetHealthAsync();

        // Assert
        await act.Should().ThrowAsync<HttpRequestException>();
    }

    private static HttpClient CreateMockHttpClient(HttpStatusCode statusCode, HttpContent content)
    {
        var handler = new MockHttpMessageHandler(statusCode, content);
        return new HttpClient(handler) { BaseAddress = new Uri("https://localhost") };
    }

    private sealed class MockHttpMessageHandler(
        HttpStatusCode statusCode,
        HttpContent content) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new HttpResponseMessage(statusCode) { Content = content });
        }
    }
}
