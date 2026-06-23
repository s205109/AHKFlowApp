using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace AHKFlowApp.API.Tests.Cors;

[Collection("WebApi")]
public sealed class CorsTests(ApiTestFixture fixture)
{
    // Sentinel origins that won't collide with anything in appsettings, so the assertions are
    // deterministic regardless of a local appsettings.Development.json.
    private const string AllowedOrigin = "http://cors-test.allowed";
    private const string DisallowedOrigin = "http://cors-test.denied";

    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task Request_FromAllowedOrigin_ReturnsAllowOriginHeader()
    {
        using WebApplicationFactory<global::Program> factory = WithAllowedOrigin();
        using HttpClient client = factory.CreateClient();

        HttpResponseMessage response = await SendWithOriginAsync(client, AllowedOrigin);

        response.Headers.GetValues("Access-Control-Allow-Origin").Should().Contain(AllowedOrigin);
    }

    [Fact]
    public async Task Request_FromDisallowedOrigin_HasNoAllowOriginHeader()
    {
        using WebApplicationFactory<global::Program> factory = WithAllowedOrigin();
        using HttpClient client = factory.CreateClient();

        HttpResponseMessage response = await SendWithOriginAsync(client, DisallowedOrigin);

        response.Headers.Contains("Access-Control-Allow-Origin").Should().BeFalse();
    }

    private WebApplicationFactory<global::Program> WithAllowedOrigin() =>
        _factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Cors:AllowedOrigins:0"] = AllowedOrigin
                })));

    private static async Task<HttpResponseMessage> SendWithOriginAsync(HttpClient client, string origin)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/health");
        request.Headers.Add("Origin", origin);
        return await client.SendAsync(request);
    }
}
