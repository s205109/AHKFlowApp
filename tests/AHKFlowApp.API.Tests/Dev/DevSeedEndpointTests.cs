using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace AHKFlowApp.API.Tests.Dev;

[Collection("WebApi")]
public sealed class DevSeedEndpointTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task SeedCategories_Returns200WithEightCategories()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/categories/seed?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        List<CategoryDto>? body = await resp.Content.ReadFromJsonAsync<List<CategoryDto>>();
        body.Should().NotBeNull();
        body!.Should().HaveCount(8);
    }

    [Fact]
    public async Task SeedHotkeys_Returns200WithAllHotkeys()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/hotkeys/seed?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await resp.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body.Should().NotBeNull();
        body!.Items.Should().HaveCount(19);
    }

    [Fact]
    public async Task SeedHotkeys_SwaggerSummary_StatesTheSeededCount()
    {
        // The summary reaches the Swagger page. Backlog 173 found it saying 17 while the catalog
        // seeded 19. The count comes from the endpoint, so a catalog change fails this test.

        // Arrange
        using HttpClient seedClient = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));
        HttpResponseMessage seeded = await seedClient.PostAsync("/api/v1/dev/hotkeys/seed?reset=true", content: null);
        seeded.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await seeded.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        int seededCount = body!.Items.Count;

        using HttpClient docClient = _factory.CreateClient();

        // Act
        await using Stream stream = await docClient.GetStreamAsync("/swagger/v1/swagger.json");
        using JsonDocument doc = await JsonDocument.ParseAsync(stream);

        // Assert
        string? summary = doc.RootElement
            .GetProperty("paths")
            .GetProperty("/api/v1/dev/hotkeys/seed")
            .GetProperty("post")
            .GetProperty("summary")
            .GetString();

        summary.Should().Contain($"Seeds {seededCount} sample hotkeys",
            "the XML summary on DevController.SeedHotkeys must state the number of hotkeys the endpoint seeds");
    }

    [Fact]
    public async Task SeedAll_ReturnsCountsAnd200_InDevelopment()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        SeedAllResultDto? result = await resp.Content.ReadFromJsonAsync<SeedAllResultDto>();
        result.Should().NotBeNull();
        result!.CategoriesCount.Should().Be(8);
        result.HotstringsCount.Should().Be(16);
        result.HotkeysCount.Should().Be(19);
    }

    [Fact]
    public async Task SeedAll_IsIdempotent_OnRepeatCall()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);
        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=false", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        SeedAllResultDto? result = await resp.Content.ReadFromJsonAsync<SeedAllResultDto>();
        result.Should().NotBeNull();
        result!.CategoriesCount.Should().Be(8);
        result.HotstringsCount.Should().Be(16);
        result.HotkeysCount.Should().Be(19);
    }

    [Fact]
    public async Task SeedAll_OutsideDevelopment_Anonymous_Returns404BeforeAuth()
    {
        using HttpClient client = _factory
            .WithWebHostBuilder(builder => builder.UseEnvironment("Test"))
            .CreateClient();

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task SeedAll_OutsideDevelopment_MissingScope_Returns404BeforeForbidden()
    {
        using WebApplicationFactory<global::Program> factory = _factory
            .WithWebHostBuilder(builder => builder.UseEnvironment("Test"));
        using HttpClient client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-Auth", "true");
        client.DefaultRequestHeaders.Add("X-Test-Oid", Guid.NewGuid().ToString());
        client.DefaultRequestHeaders.Add("X-Test-Without-Scope", "true");

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
