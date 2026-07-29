using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class KnownShortcutsApiClientTests
{
    private static KnownShortcutsApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    private static KnownShortcutCatalogDto SampleCatalog() =>
        new([
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
        ]);

    [Fact]
    public async Task ListAsync_HitsCorrectUrl()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, SampleCatalog());

        await ClientWith(handler).ListAsync();

        handler.LastRequest!.RequestUri!.PathAndQuery
            .Should().Be("/api/v1/hotkeys/known-shortcuts");
    }

    [Fact]
    public async Task ListAsync_OnSuccess_DeserializesUses()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, SampleCatalog());

        ApiResult<KnownShortcutCatalogDto> result = await ClientWith(handler).ListAsync();

        result.IsSuccess.Should().BeTrue();
        ShortcutUseDto use = result.Value!.Shortcuts.Single().Uses.Single();
        use.UsedBy.Should().Be("Windows");
        use.Scope.Should().Be(ShortcutScope.Global);
        use.Does.Should().Be("open File Explorer");
    }

    [Fact]
    public async Task ListAsync_OnServerError_ReportsFailure()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.InternalServerError);

        ApiResult<KnownShortcutCatalogDto> result = await ClientWith(handler).ListAsync();

        result.IsSuccess.Should().BeFalse();
    }

    [Fact]
    public async Task ListManagedAsync_HitsCorrectUrl()
    {
        var handler = StubHttpMessageHandler.JsonResponse(
            HttpStatusCode.OK, new ManagedKnownShortcutCatalogDto([]));

        await ClientWith(handler).ListManagedAsync();

        handler.LastRequest!.Method.Should().Be(HttpMethod.Get);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/knownshortcuts");
    }

    [Fact]
    public async Task CreateAsync_PostsToTheBasePath()
    {
        var handler = StubHttpMessageHandler.JsonResponse(
            HttpStatusCode.OK, new ManagedKnownShortcutCatalogDto([]));

        await ClientWith(handler).CreateAsync(new CreateCustomKnownShortcutDto(
            "F7", true, false, false, false, "My tool", ShortcutScope.Foreground, "open my notes"));

        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/knownshortcuts");
        handler.LastRequest.Content.Should().NotBeNull();
    }

    [Fact]
    public async Task DeleteAsync_HitsTheRecordUrl()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);
        var id = Guid.NewGuid();

        ApiResult result = await ClientWith(handler).DeleteAsync(id);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Delete);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be($"/api/v1/knownshortcuts/{id}");
    }

    [Fact]
    public async Task IgnoreAsync_PostsTheUseAsABody()
    {
        // The body is the whole point of the content-carrying no-content overload. A test that
        // only checked the URL would pass with the body dropped.
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);

        ApiResult result = await ClientWith(handler).IgnoreAsync("windows.file-explorer", "Windows");

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/knownshortcuts/ignore");
        handler.LastRequest.Content.Should().NotBeNull();
    }

    [Fact]
    public async Task RestoreAsync_PostsTheUseAsABody()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);

        ApiResult result = await ClientWith(handler).RestoreAsync("windows.file-explorer", "Windows");

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/knownshortcuts/restore");
        handler.LastRequest.Content.Should().NotBeNull();
    }

    [Fact]
    public async Task IgnoreAsync_WhenTheServerAnswers200_IsAFailure()
    {
        // The exact-204 check is deliberate: it makes the client fail loudly if a route the
        // client treats as no-content ever goes back to returning 200.
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.OK);

        ApiResult result = await ClientWith(handler).IgnoreAsync("windows.file-explorer", "Windows");

        result.IsSuccess.Should().BeFalse();
    }

    // Copied from CategoriesApiClientTests.cs. That copy is `private sealed` and nested in its own
    // test class, so it cannot be reused from here. Copy it rather than widening the original —
    // every client test file in this project carries its own.
    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;

        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;

        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });

        public static StubHttpMessageHandler StatusResponse(HttpStatusCode status) =>
            new(new HttpResponseMessage(status));

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            return Task.FromResult(_response);
        }
    }
}
