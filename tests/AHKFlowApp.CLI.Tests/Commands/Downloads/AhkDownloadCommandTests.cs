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

public sealed class AhkDownloadCommandTests : IDisposable
{
    private readonly string _baseDir;

    public AhkDownloadCommandTests()
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
        IProfilesApiClient profiles,
        Stream? stdoutSink = null,
        IAuthTokenProvider? auth = null)
    {
        IServiceProvider services = CliTestHost.WithFakes(
            hotstrings: Substitute.For<IHotstringsApiClient>(),
            profiles: profiles,
            downloads: downloads,
            auth: auth,
            binaryStdout: stdoutSink is null ? null : new BinaryStdout(() => stdoutSink),
            workingDirectory: new WorkingDirectory(() => _baseDir));

        StringWriter so = new(), se = new();
        Command cmd = AhkDownloadCommand.Build(services);
        RootCommand root = new() { cmd };
        int exit = await root.Parse(["ahk", .. args])
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    [Fact]
    public async Task HappyPath_DefaultOutput_WritesFileInBaseDir()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([1, 2, 3], "ahkflow_work.ahk", "text/plain"));

        (int exit, string stdout, string _) = await RunAsync(["--profile", "work"], downloads, profiles);

        exit.Should().Be(0);
        string expected = Path.Combine(_baseDir, "ahkflow_work.ahk");
        File.Exists(expected).Should().BeTrue();
        (await File.ReadAllBytesAsync(expected)).Should().Equal([1, 2, 3]);
        stdout.Should().Contain("Wrote").And.Contain(expected);
    }

    [Fact]
    public async Task OutputDash_WritesBytesToInjectedStream_NoLogLine()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([7, 8, 9], "ahkflow_work.ahk", "text/plain"));

        using MemoryStream sink = new();
        (int exit, string stdout, string _) = await RunAsync(
            ["--profile", "work", "-o", "-"], downloads, profiles, stdoutSink: sink);

        exit.Should().Be(0);
        sink.ToArray().Should().Equal([7, 8, 9]);
        stdout.Should().BeEmpty();
    }

    [Fact]
    public async Task UnknownProfileName_Exit2_StderrListsAvailable()
    {
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(Guid.NewGuid(), "known")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "missing"], downloads, profiles);

        exit.Should().Be(2);
        stderr.Should().Contain("Profile 'missing' not found").And.Contain("known");
    }

    [Fact]
    public async Task NotAuthenticated_Exit3_NotSignedIn()
    {
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Throws(new NotAuthenticatedException(AuthMessages.LoginRequired));

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "x"], downloads, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task ApiException401_Exit3()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Throws(new ApiException(401, "unauth"));

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "work"], downloads, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.AuthenticationFailed);
    }

    [Fact]
    public async Task ApiException404_Exit2()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Throws(new ApiException(404, "no profile"));

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "work"], downloads, profiles);

        exit.Should().Be(2);
        stderr.Should().Contain("no profile");
    }

    [Fact]
    public async Task ApiException500_Exit1()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Throws(new ApiException(500, "boom"));

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "work"], downloads, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("boom");
    }

    [Fact]
    public async Task ApiException403_StoppedWebAppHtml_Exit1_FriendlyMessage()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Throws(new ApiException(
                403,
                "<!DOCTYPE html><html><head><title>Web App - Unavailable</title></head><body><h1>Error 403 - This web app is stopped.</h1></body></html>",
                "text/html"));

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "work"], downloads, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain(ApiMessages.WebAppUnavailable);
        stderr.Should().NotContain("<!DOCTYPE html>");
    }

    [Fact]
    public async Task ProfileNameCaseInsensitive()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "MixedCase")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([1], "ahkflow_MixedCase.ahk", "text/plain"));

        (int exit, string _, string _) = await RunAsync(
            ["--profile", "mixedcase"], downloads, profiles);

        exit.Should().Be(0);
    }

    [Fact]
    public async Task FilesystemError_Exit1_StderrMessage()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Returns(new DownloadResult([1, 2, 3], "ahkflow_work.ahk", "text/plain"));

        IServiceProvider services = CliTestHost.WithFakes(
            hotstrings: Substitute.For<IHotstringsApiClient>(),
            profiles: profiles,
            downloads: downloads,
            binaryStdout: new BinaryStdout(() => throw new IOException("simulated disk error")),
            workingDirectory: new WorkingDirectory(() => _baseDir));

        StringWriter so = new(), se = new();
        Command cmd = AhkDownloadCommand.Build(services);
        RootCommand root = new() { cmd };
        int exit = await root.Parse(["ahk", "--profile", "work", "-o", "-"])
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });

        exit.Should().Be(1);
        se.ToString().Should().Contain("simulated disk error");
    }

    [Fact]
    public async Task AuthConfigurationException_Exit1()
    {
        var pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Throws(new AuthConfigurationException("ClientId is not configured."));

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "work"], downloads, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("ClientId is not configured.");
    }
}
