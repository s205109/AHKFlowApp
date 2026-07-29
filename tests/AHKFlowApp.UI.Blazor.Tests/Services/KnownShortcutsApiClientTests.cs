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
