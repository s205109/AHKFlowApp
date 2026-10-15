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
    public async Task SeedCategories_Returns200WithAllDefaultCategories()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/categories/seed?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        List<CategoryDto>? body = await resp.Content.ReadFromJsonAsync<List<CategoryDto>>();
        body.Should().NotBeNull();
        body!.Should().HaveCount(SeedCatalogCounts.Categories);
    }

    [Fact]
    public async Task SeedHotkeys_Returns200WithAllHotkeys()
    {
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()));

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/hotkeys/seed?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await resp.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body.Should().NotBeNull();
        body!.Items.Should().HaveCount(SeedCatalogCounts.Hotkeys);
    }

    [Fact]
    public async Task SeedCategories_SwaggerSummary_StatesTheSeededCount()
    {
        // Backlog 181. The summary spelled the count as a word, and no test held it.

        // Act
        string? summary = await ReadSwaggerSummaryAsync("/api/v1/dev/categories/seed");

        // Assert
        summary.Should().Contain($"Seeds {SeedCatalogCounts.Categories} default categories",
            "the XML summary on DevController.SeedCategories must state the number of categories the endpoint seeds");
    }

    [Fact]
    public async Task SeedHotkeys_SwaggerSummary_StatesTheSeededCount()
    {
        // The summary reaches the Swagger page. Backlog 173 found it saying 17 while the catalog
        // seeded 19. The count comes from the catalog, so a catalog change fails this test until
        // the summary is updated.

        // Act
        string? summary = await ReadSwaggerSummaryAsync("/api/v1/dev/hotkeys/seed");

        // Assert
        summary.Should().Contain($"Seeds {SeedCatalogCounts.Hotkeys} sample hotkeys",
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
        result!.CategoriesCount.Should().Be(SeedCatalogCounts.Categories);
        result.HotstringsCount.Should().Be(SeedCatalogCounts.Hotstrings);
        result.HotkeysCount.Should().Be(SeedCatalogCounts.Hotkeys);
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
        result!.CategoriesCount.Should().Be(SeedCatalogCounts.Categories);
        result.HotstringsCount.Should().Be(SeedCatalogCounts.Hotstrings);
        result.HotkeysCount.Should().Be(SeedCatalogCounts.Hotkeys);
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

    private async Task<string?> ReadSwaggerSummaryAsync(string path)
    {
        using HttpClient client = _factory.CreateClient();
        await using Stream stream = await client.GetStreamAsync("/swagger/v1/swagger.json");
        using JsonDocument doc = await JsonDocument.ParseAsync(stream);

        return doc.RootElement
            .GetProperty("paths")
            .GetProperty(path)
            .GetProperty("post")
            .GetProperty("summary")
            .GetString();
    }
}
