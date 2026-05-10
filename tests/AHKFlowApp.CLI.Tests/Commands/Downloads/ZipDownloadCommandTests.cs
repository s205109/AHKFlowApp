using System.CommandLine;
using AHKFlowApp.CLI.Commands.Downloads;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using AHKFlowApp.CLI.Tests.Infrastructure;
using FluentAssertions;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Commands.Downloads;

public sealed class ZipDownloadCommandTests : IDisposable
{
    private readonly string _baseDir;

    public ZipDownloadCommandTests()
    {
        _baseDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(_baseDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_baseDir)) Directory.Delete(_baseDir, recursive: true);
    }

    private async Task<(int exit, string stdout, string stderr)> RunAsync(
        string[] args,
        IDownloadsApiClient downloads,
        Stream? stdoutSink = null,
        IAuthTokenProvider? auth = null)
    {
        IServiceProvider services = CliTestHost.WithFakes(
            hotstrings: Substitute.For<IHotstringsApiClient>(),
            profiles: Substitute.For<IProfilesApiClient>(),
            downloads: downloads,
            auth: auth,
            binaryStdout: stdoutSink is null ? null : new BinaryStdout(() => stdoutSink),
            workingDirectory: new WorkingDirectory(() => _baseDir));

        StringWriter so = new(), se = new();
        Command cmd = ZipDownloadCommand.Build(services);
        RootCommand root = new() { cmd };
        int exit = await root.Parse(["zip", .. args])
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    [Fact]
    public async Task HappyPath_DefaultOutput_WritesZipInBaseDir()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([0x50, 0x4B, 0x03, 0x04], "ahkflow_scripts.zip", "application/zip"));

        (int exit, string stdout, string _) = await RunAsync([], downloads);

        exit.Should().Be(0);
        string expected = Path.Combine(_baseDir, "ahkflow_scripts.zip");
        File.Exists(expected).Should().BeTrue();
        (await File.ReadAllBytesAsync(expected)).Should().Equal([0x50, 0x4B, 0x03, 0x04]);
        stdout.Should().Contain("Wrote").And.Contain(expected);
    }

    [Fact]
    public async Task OutputDash_WritesBytesToInjectedStream_NoLogLine()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([1, 2, 3, 4, 5], "ahkflow_scripts.zip", "application/zip"));

        using MemoryStream sink = new();
        (int exit, string stdout, string _) = await RunAsync(["-o", "-"], downloads, stdoutSink: sink);

        exit.Should().Be(0);
        sink.ToArray().Should().Equal([1, 2, 3, 4, 5]);
        stdout.Should().BeEmpty();
    }

    [Fact]
    public async Task OutputDir_WritesFileInside()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([1, 2, 3], "ahkflow_scripts.zip", "application/zip"));

        string targetDir = Path.Combine(_baseDir, "outdir");
        Directory.CreateDirectory(targetDir);

        (int exit, string _, string _) = await RunAsync(["-o", targetDir], downloads);

        exit.Should().Be(0);
        File.Exists(Path.Combine(targetDir, "ahkflow_scripts.zip")).Should().BeTrue();
    }

    [Fact]
    public async Task OutputFile_WritesExactPath()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([1, 2, 3], "ahkflow_scripts.zip", "application/zip"));

        string explicitPath = Path.Combine(_baseDir, "renamed.zip");

        (int exit, string _, string _) = await RunAsync(["-o", explicitPath], downloads);

        exit.Should().Be(0);
        File.Exists(explicitPath).Should().BeTrue();
    }

    [Fact]
    public async Task NotAuthenticated_Exit3_NotSignedIn()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Throws(new NotAuthenticatedException(AuthMessages.LoginRequired));

        (int exit, string _, string stderr) = await RunAsync([], downloads);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task ApiException401_Exit3()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Throws(new ApiException(401, "unauth"));

        (int exit, string _, string stderr) = await RunAsync([], downloads);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.AuthenticationFailed);
    }

    [Fact]
    public async Task ApiException404_Exit2()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Throws(new ApiException(404, "no profiles"));

        (int exit, string _, string stderr) = await RunAsync([], downloads);

        exit.Should().Be(2);
        stderr.Should().Contain("no profiles");
    }

    [Fact]
    public async Task ApiException500_Exit1()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Throws(new ApiException(500, "kaboom"));

        (int exit, string _, string stderr) = await RunAsync([], downloads);

        exit.Should().Be(1);
        stderr.Should().Contain("kaboom");
    }
}
