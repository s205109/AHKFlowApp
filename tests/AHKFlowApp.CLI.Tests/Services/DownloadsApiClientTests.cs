using System.Net;
using System.Net.Http.Headers;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class DownloadsApiClientTests
{
    private static (DownloadsApiClient client, StubHandler handler) CreateClient(
        Func<HttpRequestMessage, HttpResponseMessage> respond)
    {
        StubHandler handler = new(respond);
        HttpClient http = new(handler) { BaseAddress = new Uri("http://test/") };
        return (new DownloadsApiClient(http), handler);
    }

    [Fact]
    public async Task GetProfileScript_HappyPath_ReturnsBytesFilenameAndContentType()
    {
        var id = Guid.NewGuid();
        (DownloadsApiClient sut, _) = CreateClient(_ =>
        {
            HttpResponseMessage r = new(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([1, 2, 3]),
            };
            r.Content.Headers.ContentType = new MediaTypeHeaderValue("text/plain") { CharSet = "utf-8" };
            r.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment")
            {
                FileName = "ahkflow_work.ahk",
            };
            return r;
        });

        DownloadResult result = await sut.GetProfileScriptAsync(id, CancellationToken.None);

        result.Bytes.Should().Equal([1, 2, 3]);
        result.FileName.Should().Be("ahkflow_work.ahk");
        result.ContentType.Should().StartWith("text/plain");
    }

    [Fact]
    public async Task GetProfileScript_PrefersFileNameStarOverFileName()
    {
        (DownloadsApiClient sut, _) = CreateClient(_ =>
        {
            HttpResponseMessage r = new(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([0]),
            };
            r.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment")
            {
                FileName = "fallback.ahk",
                FileNameStar = "preferred_naïve.ahk",
            };
            return r;
        });

        DownloadResult result = await sut.GetProfileScriptAsync(Guid.NewGuid(), CancellationToken.None);

        result.FileName.Should().Be("preferred_naïve.ahk");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("../escape.ahk")]
    [InlineData("..\\escape.ahk")]
    [InlineData("sub/dir.ahk")]
    [InlineData("/rooted/path.ahk")]
    [InlineData(".")]
    [InlineData("..")]
    [InlineData("NUL")]
    [InlineData("NUL.ahk")]
    [InlineData("CON")]
    [InlineData("CON.ahk")]
    public async Task GetProfileScript_UnsafeOrMissingFilename_FallsBackToProfileAhk(string? bad)
    {
        (DownloadsApiClient sut, _) = CreateClient(_ =>
        {
            HttpResponseMessage r = new(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([0]),
            };
            if (bad is not null)
            {
                r.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment")
                {
                    FileName = bad,
                };
            }
            return r;
        });

        DownloadResult result = await sut.GetProfileScriptAsync(Guid.NewGuid(), CancellationToken.None);

        result.FileName.Should().Be("profile.ahk");
    }

    [Fact]
    public async Task GetProfileScript_NonSuccess_ThrowsApiExceptionWithStatusAndBody()
    {
        (DownloadsApiClient sut, _) = CreateClient(_ =>
            new HttpResponseMessage(HttpStatusCode.NotFound)
            {
                Content = new StringContent("not your profile"),
            });

        Func<Task> act = async () => await sut.GetProfileScriptAsync(Guid.NewGuid(), CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(404);
        ex.Body.Should().Be("not your profile");
    }

    [Fact]
    public async Task GetProfileScript_HitsExpectedRoute()
    {
        var id = Guid.NewGuid();
        (DownloadsApiClient sut, StubHandler handler) = CreateClient(_ =>
            new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([0]) });

        await sut.GetProfileScriptAsync(id, CancellationToken.None);

        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be($"/api/v1/downloads/{id}");
        handler.LastRequest.Method.Should().Be(HttpMethod.Get);
    }

    [Fact]
    public async Task GetAllZip_HappyPath_ReturnsZipBytesAndConstantFilename()
    {
        (DownloadsApiClient sut, _) = CreateClient(_ =>
        {
            HttpResponseMessage r = new(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([0x50, 0x4B, 0x03, 0x04]),
            };
            r.Content.Headers.ContentType = new MediaTypeHeaderValue("application/zip");
            r.Content.Headers.ContentDisposition = new ContentDispositionHeaderValue("attachment")
            {
                FileName = "ahkflow_scripts.zip",
            };
            return r;
        });

        DownloadResult result = await sut.GetAllProfileScriptsZipAsync(CancellationToken.None);

        result.FileName.Should().Be("ahkflow_scripts.zip");
        result.ContentType.Should().Be("application/zip");
    }

    [Fact]
    public async Task GetAllZip_MissingFilename_FallsBackToZipConstant()
    {
        (DownloadsApiClient sut, _) = CreateClient(_ =>
            new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([0]) });

        DownloadResult result = await sut.GetAllProfileScriptsZipAsync(CancellationToken.None);

        result.FileName.Should().Be("ahkflow_scripts.zip");
    }

    [Fact]
    public async Task GetAllZip_HitsExpectedRoute()
    {
        (DownloadsApiClient sut, StubHandler handler) = CreateClient(_ =>
            new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([0]) });

        await sut.GetAllProfileScriptsZipAsync(CancellationToken.None);

        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be("/api/v1/downloads/zip");
        handler.LastRequest.Method.Should().Be(HttpMethod.Get);
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequest = request;
            return Task.FromResult(respond(request));
        }
    }
}
