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

    [Fact]
    public async Task SwaggerJson_HotstringExamples_SurfacesBothBtwAndRawExamples()
    {
        // Swashbuckle.AspNetCore.Filters resolves one IExamplesProvider<T> per T — a second
        // provider targeting an already-covered type (HotstringDto/CreateHotstringDto/
        // UpdateHotstringDto/HotstringPreviewRequestDto/HotstringPreviewDto) would silently
        // replace its example everywhere. This guards against that: the Raw example
        // (targeting HotstringHistoryVersionDto, previously uncovered) must not have knocked out
        // the pre-existing "btw" example.

        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        string json = await client.GetStringAsync("/swagger/v1/swagger.json");

        // Assert
        json.Should().Contain("by the way", "the original 'btw' example must still be present");
        json.Should().Contain("MsgBox A_AhkVersion", "the new Raw example must be present");
    }
}
