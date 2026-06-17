using System.CommandLine;
using System.IO.Compression;
using System.Text;
using AHKFlowApp.API;
using AHKFlowApp.CLI.Commands.Downloads;
using AHKFlowApp.CLI.Services;
using AHKFlowApp.CLI.Tests.Infrastructure;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Integration;

[Collection("CliWebApi")]
public sealed class DownloadCliIntegrationTests(SqlContainerFixture sql) : IAsyncLifetime, IDisposable
{
    private WebApplicationFactory<Program> _factory = null!;
    private CustomWebApplicationFactory _baseFactory = null!;
    private readonly Guid _testUserOid = Guid.NewGuid();
    private readonly string _baseDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

    public Task InitializeAsync()
    {
        Directory.CreateDirectory(_baseDir);
        _baseFactory = new CustomWebApplicationFactory(sql);
        _factory = _baseFactory.WithTestAuth(u => u.WithOid(_testUserOid).WithEmail("test@example.com"));
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
        await _baseFactory.DisposeAsync();
    }

    public void Dispose()
    {
        if (Directory.Exists(_baseDir)) Directory.Delete(_baseDir, recursive: true);
    }

    private async Task<(int exit, string stdout, string stderr, byte[] stdoutBytes)> RunAsync(
        string[] args, string? token = "test-token")
    {
        using MemoryStream sink = new();
        IServiceProvider services = CliTestHost.WithFactory(
            _factory, token, counter: null, stdoutSink: sink, baseDirectory: _baseDir);
        StringWriter so = new(), se = new();
        RootCommand root = new() { DownloadCommand.Build(services) };
        int exit = await root.Parse(args)
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString(), sink.ToArray());
    }

    private async Task<Profile> SeedProfileAsync(string name, bool isDefault = false)
    {
        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Profile p = new ProfileBuilder().WithOwner(_testUserOid).WithName(name).AsDefault(isDefault).Build();
        db.Profiles.Add(p);
        await db.SaveChangesAsync();
        return p;
    }

    private async Task<Hotstring> SeedHotstringAsync(string trigger, string replacement, Guid? profileId = null)
    {
        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        HotstringBuilder b = new HotstringBuilder()
            .WithOwner(_testUserOid)
            .WithTrigger(trigger)
            .WithReplacement(replacement);
        if (profileId is { } pid) b = b.InProfile(pid);
        Hotstring h = b.Build();
        db.Hotstrings.Add(h);
        await db.SaveChangesAsync();
        return h;
    }

    [Fact]
    public async Task Ahk_Default_WritesFileWithSeededHotstringContent()
    {
        Profile p = await SeedProfileAsync("work");
        await SeedHotstringAsync("scoped1", "scoped expansion", p.Id);
        await SeedHotstringAsync("global1", "global expansion");

        (int exit, string stdout, string _, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work"]);

        exit.Should().Be(0);
        string expected = Path.Combine(_baseDir, $"ahkflow_{p.Name}.ahk");
        File.Exists(expected).Should().BeTrue();

        string content = await File.ReadAllTextAsync(expected, Encoding.UTF8);
        content.Should().Contain("scoped1").And.Contain("scoped expansion");
        content.Should().Contain("global1").And.Contain("global expansion");
        stdout.Should().Contain("Wrote");
    }

    [Fact]
    public async Task Ahk_OutputDir_WritesFileInsideExistingDir()
    {
        await SeedProfileAsync("work");
        string targetDir = Path.Combine(_baseDir, "out-existing");
        Directory.CreateDirectory(targetDir);

        (int exit, string _, string _, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work", "-o", targetDir]);

        exit.Should().Be(0);
        Directory.GetFiles(targetDir, "ahkflow_*.ahk").Should().HaveCount(1);
    }

    [Fact]
    public async Task Ahk_OutputDirTrailingSep_CreatesAndWrites()
    {
        await SeedProfileAsync("work");
        string targetDir = Path.Combine(_baseDir, "new-dir") + Path.DirectorySeparatorChar;

        (int exit, string _, string _, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work", "-o", targetDir]);

        exit.Should().Be(0);
        Directory.Exists(targetDir).Should().BeTrue();
        Directory.GetFiles(targetDir, "ahkflow_*.ahk").Should().HaveCount(1);
    }

    [Fact]
    public async Task Ahk_OutputFile_WritesExactPath()
    {
        await SeedProfileAsync("work");
        string explicitPath = Path.Combine(_baseDir, "custom.ahk");

        (int exit, string _, string _, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work", "-o", explicitPath]);

        exit.Should().Be(0);
        File.Exists(explicitPath).Should().BeTrue();
    }

    [Fact]
    public async Task Ahk_OutputDash_WritesBytesToInjectedStream()
    {
        await SeedProfileAsync("work");

        (int exit, string stdout, string _, byte[] stdoutBytes) = await RunAsync(
            ["download", "ahk", "--profile", "work", "-o", "-"]);

        exit.Should().Be(0);
        stdoutBytes.Length.Should().BeGreaterThan(0);
        stdout.Should().BeEmpty();
    }

    [Fact]
    public async Task Ahk_UnknownProfile_Exit2()
    {
        await SeedProfileAsync("known");

        (int exit, string _, string stderr, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "missing"]);

        exit.Should().Be(2);
        stderr.Should().Contain("Profile 'missing' not found");
    }

    [Fact]
    public async Task Zip_Default_WritesValidZipWithSeededContent()
    {
        Profile a = await SeedProfileAsync("a");
        Profile b = await SeedProfileAsync("b");
        await SeedHotstringAsync("trigA", "expansionA", a.Id);
        await SeedHotstringAsync("trigB", "expansionB", b.Id);

        (int exit, string _, string _, byte[] _) = await RunAsync(["download", "zip"]);

        exit.Should().Be(0);
        string zipPath = Path.Combine(_baseDir, "ahkflow_scripts.zip");
        File.Exists(zipPath).Should().BeTrue();

        await using FileStream fs = File.OpenRead(zipPath);
        using ZipArchive zip = new(fs, ZipArchiveMode.Read);
        zip.Entries.Should().HaveCountGreaterThanOrEqualTo(2);

        string allContent = await ReadAllEntriesAsync(zip);
        allContent.Should().Contain("trigA").And.Contain("expansionA");
        allContent.Should().Contain("trigB").And.Contain("expansionB");
    }

    [Fact]
    public async Task Zip_OutputDash_WritesValidZipBytesToInjectedStream()
    {
        Profile a = await SeedProfileAsync("a");
        await SeedHotstringAsync("dashTrig", "dashReplacement", a.Id);

        (int exit, string _, string _, byte[] stdoutBytes) = await RunAsync(
            ["download", "zip", "-o", "-"]);

        exit.Should().Be(0);
        using MemoryStream ms = new(stdoutBytes);
        using ZipArchive zip = new(ms, ZipArchiveMode.Read);
        zip.Entries.Should().NotBeEmpty();

        string allContent = await ReadAllEntriesAsync(zip);
        allContent.Should().Contain("dashTrig").And.Contain("dashReplacement");
    }

    [Fact]
    public async Task Auth_TokenUnset_Exit3()
    {
        await SeedProfileAsync("work");

        (int exit, string _, string stderr, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work"], token: null);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task Overwrite_Silent()
    {
        Profile p = await SeedProfileAsync("work");
        string expected = Path.Combine(_baseDir, $"ahkflow_{p.Name}.ahk");
        await File.WriteAllTextAsync(expected, "STALE", Encoding.UTF8);

        (int exit, string _, string _, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work"]);

        exit.Should().Be(0);
        string fresh = await File.ReadAllTextAsync(expected, Encoding.UTF8);
        fresh.Should().NotBe("STALE");
    }

    private static async Task<string> ReadAllEntriesAsync(ZipArchive zip)
    {
        StringBuilder sb = new();
        foreach (ZipArchiveEntry entry in zip.Entries)
        {
            await using Stream s = await entry.OpenAsync();
            using StreamReader reader = new(s, Encoding.UTF8);
            sb.AppendLine(await reader.ReadToEndAsync());
        }
        return sb.ToString();
    }
}
