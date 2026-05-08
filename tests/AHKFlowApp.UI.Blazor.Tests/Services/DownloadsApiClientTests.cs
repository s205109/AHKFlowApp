using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class DownloadsApiClientTests
{
    private static DownloadsApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task GetProfileScriptAsync_OnSuccess_ReturnsBytesAndServerFileName()
    {
        var handler = StubHttpMessageHandler.BinaryResponse(
            HttpStatusCode.OK,
            "text/plain; charset=utf-8",
            Encoding.UTF8.GetBytes("script body"),
            fileDownloadName: "ahkflow_Work.ahk");

        ApiResult<FileDownload> result = await ClientWith(handler).GetProfileScriptAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeTrue();
        result.Value!.FileName.Should().Be("ahkflow_Work.ahk");
        result.Value.ContentType.Should().Be("text/plain; charset=utf-8");
        Encoding.UTF8.GetString(result.Value.Content).Should().Be("script body");
    }

    [Fact]
    public async Task GetProfileScriptAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var problem = new ApiProblemDetails(null, "Not Found", 404, "Profile not found", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, problem);

        ApiResult<FileDownload> result = await ClientWith(handler).GetProfileScriptAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    [Fact]
    public async Task GetAllProfileScriptsZipAsync_OnSuccess_ReturnsZipBytesAndFileName()
    {
        byte[] body = [0x50, 0x4B, 0x05, 0x06];
        var handler = StubHttpMessageHandler.BinaryResponse(
            HttpStatusCode.OK, "application/zip", body, fileDownloadName: "ahkflow_scripts.zip");

        ApiResult<FileDownload> result = await ClientWith(handler).GetAllProfileScriptsZipAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.FileName.Should().Be("ahkflow_scripts.zip");
        result.Value.ContentType.Should().Be("application/zip");
        result.Value.Content.Should().Equal(body);
    }

    [Fact]
    public async Task GetProfileScriptAsync_NetworkError_ReturnsNetworkErrorResult()
    {
        var handler = StubHttpMessageHandler.ThrowingHandler();

        ApiResult<FileDownload> result = await ClientWith(handler).GetProfileScriptAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NetworkError);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private readonly bool _throw;

        private StubHttpMessageHandler(HttpResponseMessage response, bool @throw = false)
        {
            _response = response;
            _throw = @throw;
        }

        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });

        public static StubHttpMessageHandler BinaryResponse(HttpStatusCode status, string contentType, byte[] body, string fileDownloadName)
        {
            var content = new ByteArrayContent(body);
            content.Headers.ContentType = MediaTypeHeaderValue.Parse(contentType);
            content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment") { FileName = fileDownloadName };
            return new(new HttpResponseMessage(status) { Content = content });
        }

        public static StubHttpMessageHandler ThrowingHandler() =>
            new(new HttpResponseMessage(HttpStatusCode.OK), @throw: true);

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            if (_throw) throw new HttpRequestException("Network error");
            return Task.FromResult(_response);
        }
    }
}
