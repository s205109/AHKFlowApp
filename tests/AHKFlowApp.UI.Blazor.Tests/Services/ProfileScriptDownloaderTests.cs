using System.Net;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

/// <summary>
/// The API decides the file name, so this service only puts the timestamp in front of it. The
/// stem rule is pinned once, by <c>AhkFileNamingTests</c> in the Application tests.
/// </summary>
public sealed class ProfileScriptDownloaderTests
{
    private readonly IDownloadsApiClient _downloads = Substitute.For<IDownloadsApiClient>();
    private readonly IFileSaver _saver = Substitute.For<IFileSaver>();
    private readonly FakeTimeProvider _clock = new(new DateTimeOffset(2026, 7, 26, 14, 5, 9, TimeSpan.Zero));

    private ProfileScriptDownloader CreateSut() => new(_downloads, _saver, _clock);

    private static readonly Guid ProfileId = Guid.NewGuid();

    private void StubScript(
        string apiFileName = "ahkflow_Work.ahk",
        byte[]? content = null,
        string contentType = "text/plain; charset=utf-8") =>
        _downloads.GetProfileScriptAsync(ProfileId, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(
                new FileDownload(content ?? [0x41, 0x42], apiFileName, contentType)));

    [Fact]
    public async Task DownloadAsync_Success_SavesUnderTheApiFileNameWithAStamp()
    {
        // Backlog 171. The UI used to build its own stem from the profile name. Any name the API
        // sends must come through unchanged, behind the stamp.
        StubScript(apiFileName: "ahkflow_Named_By_The_Api.ahk");

        DownloadOutcome outcome = await CreateSut().DownloadAsync(ProfileId, CancellationToken.None);

        outcome.Saved.Should().BeTrue();
        outcome.FileName.Should().Be("20260726_140509_ahkflow_Named_By_The_Api.ahk");
    }

    [Fact]
    public async Task DownloadAsync_ResponseWithoutContentDisposition_SavesUnderTheFallbackName()
    {
        // Backlog 171. A browser hides Content-Disposition from a page on another origin unless the
        // API exposes it. This runs the real API client, so it proves that the client's fallback
        // name is the name the owner gets.
        DownloadsApiClient client = new(new HttpClient(new StubHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([0x41, 0x42]) }))
        {
            BaseAddress = new Uri("http://localhost/"),
        });
        ProfileScriptDownloader sut = new(client, _saver, _clock);

        DownloadOutcome outcome = await sut.DownloadAsync(ProfileId, CancellationToken.None);

        outcome.Saved.Should().BeTrue();
        outcome.FileName.Should().Be("20260726_140509_ahkflow_profile.ahk");
    }

    [Fact]
    public async Task DownloadAsync_Success_SavesWithStampedNameAndPayload()
    {
        byte[] content = [0x41, 0x42, 0x43];
        StubScript(content: content);

        DownloadOutcome outcome = await CreateSut().DownloadAsync(ProfileId, CancellationToken.None);

        outcome.Saved.Should().BeTrue();
        outcome.FileName.Should().Be("20260726_140509_ahkflow_Work.ahk");
        outcome.Error.Should().BeNull();
        await _saver.Received(1).SaveAsync(
            "20260726_140509_ahkflow_Work.ahk",
            "text/plain; charset=utf-8",
            Arg.Is<byte[]>(b => b.SequenceEqual(content)));
    }

    [Fact]
    public async Task DownloadAsync_ApiFailure_ReturnsFailureAndSavesNothing()
    {
        _downloads.GetProfileScriptAsync(ProfileId, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Failure(ApiResultStatus.NetworkError, null));

        DownloadOutcome outcome = await CreateSut().DownloadAsync(ProfileId, CancellationToken.None);

        outcome.Saved.Should().BeFalse();
        outcome.FileName.Should().BeNull();
        outcome.Error.Should().Be("Unable to reach the API. Check your connection and try again.");
        await _saver.DidNotReceive().SaveAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<byte[]>());
    }

    [Fact]
    public async Task DownloadAsync_ApiCancelled_PropagatesAndSavesNothing()
    {
        _downloads.GetProfileScriptAsync(ProfileId, Arg.Any<CancellationToken>())
            .Throws(new OperationCanceledException());

        Func<Task> act = async () => _ = await CreateSut().DownloadAsync(ProfileId, CancellationToken.None);

        await act.Should().ThrowAsync<OperationCanceledException>();
        await _saver.DidNotReceive().SaveAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<byte[]>());
    }

    [Fact]
    public async Task DownloadAsync_FileSaverThrows_PropagatesUnchanged()
    {
        StubScript();
        InvalidOperationException boom = new("save failed");
        _saver.SaveAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<byte[]>()).Throws(boom);

        Func<Task> act = async () => _ = await CreateSut().DownloadAsync(ProfileId, CancellationToken.None);

        (await act.Should().ThrowAsync<InvalidOperationException>()).Which.Should().BeSameAs(boom);
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(responder(request));
    }
}
