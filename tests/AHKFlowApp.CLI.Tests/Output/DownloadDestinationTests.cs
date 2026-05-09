using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Output;

public sealed class DownloadDestinationTests : IDisposable
{
    private readonly string _baseDir;

    public DownloadDestinationTests()
    {
        _baseDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(_baseDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_baseDir)) Directory.Delete(_baseDir, recursive: true);
    }

    [Fact]
    public void Resolve_NullOption_UsesBaseDirAndServerName()
    {
        DownloadTarget t = DownloadDestination.Resolve(null, "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.FileTarget>();
        ((DownloadTarget.FileTarget)t).Path.Should().Be(Path.Combine(_baseDir, "foo.ahk"));
    }

    [Fact]
    public void Resolve_Dash_ReturnsStdout()
    {
        DownloadTarget t = DownloadDestination.Resolve("-", "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.StdoutTarget>();
    }

    [Fact]
    public void Resolve_TrailingSeparator_TreatsAsDirectory()
    {
        string newDir = Path.Combine(_baseDir, "newsubdir") + Path.DirectorySeparatorChar;

        DownloadTarget t = DownloadDestination.Resolve(newDir, "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.FileTarget>();
        ((DownloadTarget.FileTarget)t).Path.Should().Be(Path.Combine(_baseDir, "newsubdir", "foo.ahk"));
    }

    [Fact]
    public void Resolve_ExistingDirectory_TreatsAsDirectory()
    {
        DownloadTarget t = DownloadDestination.Resolve(_baseDir, "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.FileTarget>();
        ((DownloadTarget.FileTarget)t).Path.Should().Be(Path.Combine(_baseDir, "foo.ahk"));
    }

    [Fact]
    public void Resolve_NonExistentNonTrailing_TreatsAsExactFilePath()
    {
        string explicitFile = Path.Combine(_baseDir, "explicit.ahk");

        DownloadTarget t = DownloadDestination.Resolve(explicitFile, "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.FileTarget>();
        ((DownloadTarget.FileTarget)t).Path.Should().Be(explicitFile);
    }

    [Fact]
    public void Resolve_RelativeFilePath_NormalizesAgainstBaseDirectory()
    {
        DownloadTarget t = DownloadDestination.Resolve("custom.ahk", "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.FileTarget>();
        ((DownloadTarget.FileTarget)t).Path.Should().Be(Path.Combine(_baseDir, "custom.ahk"));
    }

    [Fact]
    public void Resolve_RelativeDirTrailingSep_NormalizesAndJoinsServerName()
    {
        DownloadTarget t = DownloadDestination.Resolve("subdir/", "foo.ahk", _baseDir);

        t.Should().BeOfType<DownloadTarget.FileTarget>();
        ((DownloadTarget.FileTarget)t).Path.Should().Be(Path.Combine(_baseDir, "subdir", "foo.ahk"));
    }

    [Fact]
    public async Task WriteAsync_FileTarget_WritesBytesAndCreatesParentDirs()
    {
        string nested = Path.Combine(_baseDir, "a", "b", "out.ahk");
        byte[] bytes = [1, 2, 3, 4];

        await DownloadDestination.WriteAsync(
            DownloadTarget.File(nested), bytes, new BinaryStdout(() => new MemoryStream()), CancellationToken.None);

        File.Exists(nested).Should().BeTrue();
        (await File.ReadAllBytesAsync(nested)).Should().Equal(bytes);
    }

    [Fact]
    public async Task WriteAsync_FileTarget_OverwritesExistingFile()
    {
        string path = Path.Combine(_baseDir, "exists.ahk");
        await File.WriteAllBytesAsync(path, [9, 9, 9]);
        byte[] newBytes = [1, 2];

        await DownloadDestination.WriteAsync(
            DownloadTarget.File(path), newBytes, new BinaryStdout(() => new MemoryStream()), CancellationToken.None);

        (await File.ReadAllBytesAsync(path)).Should().Equal(newBytes);
    }

    [Fact]
    public async Task WriteAsync_StdoutTarget_WritesBytesToInjectedStream()
    {
        using MemoryStream sink = new();
        byte[] bytes = [42, 43, 44];

        await DownloadDestination.WriteAsync(
            DownloadTarget.Stdout, bytes, new BinaryStdout(() => sink), CancellationToken.None);

        sink.ToArray().Should().Equal(bytes);
    }
}
