using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

/// <summary>
/// The file-name rules are the reason this service exists, so they are pinned here rather than
/// through a page. The rules run in one fixed order: collapse unsafe characters, truncate to 64
/// characters, trim edge underscores, then fall back to "profile" when nothing is left.
/// </summary>
public sealed class ProfileScriptDownloaderTests
{
    private const string Stamp = "20260726_140509";

    private readonly IDownloadsApiClient _downloads = Substitute.For<IDownloadsApiClient>();
    private readonly IFileSaver _saver = Substitute.For<IFileSaver>();
    private readonly FakeTimeProvider _clock = new(new DateTimeOffset(2026, 7, 26, 14, 5, 9, TimeSpan.Zero));

    private ProfileScriptDownloader CreateSut() => new(_downloads, _saver, _clock);

    private static readonly Guid ProfileId = Guid.NewGuid();

    private void StubScript(byte[]? content = null, string contentType = "text/plain; charset=utf-8") =>
        _downloads.GetProfileScriptAsync(ProfileId, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(
                new FileDownload(content ?? [0x41, 0x42], "ahkflow.ahk", contentType)));

    private async Task<string> SavedNameForAsync(string profileName)
    {
        StubScript();
        DownloadOutcome outcome = await CreateSut().DownloadAsync(ProfileId, profileName, CancellationToken.None);
        outcome.Saved.Should().BeTrue();
        return outcome.FileName!;
    }

    private static string StemOf(string fileName)
    {
        const string prefix = $"{Stamp}_ahkflow_";
        fileName.Should().StartWith(prefix).And.EndWith(".ahk");
        return fileName[prefix.Length..^".ahk".Length];
    }

    [Fact]
    public async Task DownloadAsync_UnsafeCharacters_CollapseToOneUnderscore()
    {
        string name = await SavedNameForAsync("Work   //  Notes");

        StemOf(name).Should().Be("Work_Notes");
    }

    [Fact]
    public async Task DownloadAsync_EdgeUnsafeCharacters_AreTrimmed()
    {
        string name = await SavedNameForAsync("  Work  ");

        StemOf(name).Should().Be("Work");
    }

    [Fact]
    public async Task DownloadAsync_NameWithNoSafeCharacters_FallsBackToProfile()
    {
        string name = await SavedNameForAsync("///");

        StemOf(name).Should().Be("profile");
    }

    [Fact]
    public async Task DownloadAsync_StemLongerThan64Characters_IsTruncatedTo64()
    {
        string name = await SavedNameForAsync(new string('a', 80));

        StemOf(name).Should().Be(new string('a', 64));
    }

    [Fact]
    public async Task DownloadAsync_TruncationLandsOnAnUnderscore_LeavesNoTrailingUnderscore()
    {
        // Collapses to 65 characters: 63 'a', then '_', then 'x'. Truncating to 64 keeps the
        // underscore at the end, so the trim has to run after the cut, not before it.
        string name = await SavedNameForAsync(new string('a', 63) + " x");

        StemOf(name).Should().Be(new string('a', 63));
    }

    [Fact]
    public async Task DownloadAsync_DotsAndDashes_SurviveUnchanged()
    {
        string name = await SavedNameForAsync("work-v2.1");

        StemOf(name).Should().Be("work-v2.1");
    }

    [Fact]
    public async Task DownloadAsync_Success_SavesWithStampedNameAndPayload()
    {
        byte[] content = [0x41, 0x42, 0x43];
        StubScript(content, "text/plain; charset=utf-8");

        DownloadOutcome outcome = await CreateSut().DownloadAsync(ProfileId, "Work", CancellationToken.None);

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

        DownloadOutcome outcome = await CreateSut().DownloadAsync(ProfileId, "Work", CancellationToken.None);

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

        Func<Task> act = async () => _ = await CreateSut().DownloadAsync(ProfileId, "Work", CancellationToken.None);

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

        Func<Task> act = async () => _ = await CreateSut().DownloadAsync(ProfileId, "Work", CancellationToken.None);

        (await act.Should().ThrowAsync<InvalidOperationException>()).Which.Should().BeSameAs(boom);
    }
}
