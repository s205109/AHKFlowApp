using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.API.Models;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Version;

[Collection("WebApi")]
public sealed class VersionControllerTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task GetVersion_Returns200WithNonEmptyVersion()
    {
        // Arrange
        using HttpClient client = _factory.CreateClient();

        // Act
        HttpResponseMessage response = await client.GetAsync("/api/v1/version");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        VersionResponse? body = await response.Content.ReadFromJsonAsync<VersionResponse>();
        body.Should().NotBeNull();
        body!.Version.Should().NotBeNullOrWhiteSpace();
    }

    public void Dispose() => _factory.Dispose();
}
