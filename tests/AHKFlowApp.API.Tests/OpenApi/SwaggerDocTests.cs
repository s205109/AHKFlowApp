using System.Text.Json;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.OpenApi;

[Collection("WebApi")]
public sealed class SwaggerDocTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task SwaggerJson_HotstringDtoSchema_SurfacesPropertyDescriptions()
    {
        // Confirms AHKFlowApp.Application.xml is wired into Swagger.
        // If the wiring breaks, schema property descriptions disappear.

        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        await using Stream stream = await client.GetStreamAsync("/swagger/v1/swagger.json");
        using JsonDocument doc = await JsonDocument.ParseAsync(stream);

        // Assert
        JsonElement properties = doc.RootElement
            .GetProperty("components")
            .GetProperty("schemas")
            .GetProperty("HotstringDto")
            .GetProperty("properties");

        bool anyDescribed = properties.EnumerateObject()
            .Any(p => p.Value.TryGetProperty("description", out JsonElement description)
                      && !string.IsNullOrWhiteSpace(description.GetString()));

        anyDescribed.Should().BeTrue(
            "HotstringDto property descriptions must be surfaced from AHKFlowApp.Application.xml");
    }
}
