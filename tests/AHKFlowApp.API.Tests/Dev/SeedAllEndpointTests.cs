using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Dev;

[Collection("WebApi")]
public sealed class SeedAllEndpointTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    [Fact]
    public async Task SeedAll_ReturnsCountsAnd200_InDevelopment()
    {
        using HttpClient client = _factory
            .WithTestAuth(b => b.WithOid(Guid.NewGuid()))
            .CreateClient();

        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        SeedAllResultDto? result = await resp.Content.ReadFromJsonAsync<SeedAllResultDto>();
        result.Should().NotBeNull();
        result!.CategoriesCount.Should().Be(8);
        result.HotstringsCount.Should().Be(12);
        result.HotkeysCount.Should().Be(12);
    }

    [Fact]
    public async Task SeedAll_IsIdempotent_OnRepeatCall()
    {
        using HttpClient client = _factory
            .WithTestAuth(b => b.WithOid(Guid.NewGuid()))
            .CreateClient();

        await client.PostAsync("/api/v1/dev/seed-all?reset=true", content: null);
        HttpResponseMessage resp = await client.PostAsync("/api/v1/dev/seed-all?reset=false", content: null);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        SeedAllResultDto? result = await resp.Content.ReadFromJsonAsync<SeedAllResultDto>();
        result.Should().NotBeNull();
        result!.CategoriesCount.Should().Be(8);
        result.HotstringsCount.Should().Be(12);
        result.HotkeysCount.Should().Be(12);
    }

    public void Dispose() => _factory.Dispose();
}
