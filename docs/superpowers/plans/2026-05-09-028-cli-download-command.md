# 028 — CLI download command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up `ahkflow download ahk --profile <name>` and `ahkflow download zip` so users can fetch generated AutoHotkey scripts via the CLI, defaulting to writing the server-named file into the current directory and supporting `-o <path>` / `-o -` (stdout).

**Architecture:** Mirror 018's CLI patterns. Add a `DownloadsApiClient` impl over the existing `IDownloadsApiClient` interface, route both commands through a shared `DownloadDestination` helper, and introduce two tiny DI-registered seams (`BinaryStdout`, `WorkingDirectory`) so tests don't touch `Console` or `Environment.CurrentDirectory`. Sanitise the server-supplied filename at the API client boundary.

**Tech Stack:** .NET 10, `System.CommandLine` v3 preview, `Microsoft.Extensions.Http` (typed clients + standard resilience), xUnit + FluentAssertions + NSubstitute, Testcontainers (SQL Server) via the existing `[Collection("CliWebApi")]`.

**Spec:** [`docs/superpowers/specs/2026-05-09-028-cli-download-command-design.md`](../specs/2026-05-09-028-cli-download-command-design.md)

**Branch:** `feature/028-cli-download-command` (already created)

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `src/Tools/AHKFlowApp.CLI/Services/BinaryStdout.cs` | DI seam wrapping `Console.OpenStandardOutput()`. |
| Create | `src/Tools/AHKFlowApp.CLI/Services/WorkingDirectory.cs` | DI seam wrapping `Environment.CurrentDirectory`. |
| Create | `src/Tools/AHKFlowApp.CLI/Services/DownloadsApiClient.cs` | Typed HttpClient impl of `IDownloadsApiClient`. |
| Create | `src/Tools/AHKFlowApp.CLI/Output/DownloadDestination.cs` | `DownloadTarget` union + `Resolve` + `WriteAsync`. |
| Create | `src/Tools/AHKFlowApp.CLI/Exceptions/ProfileNotFoundException.cs` | Sentinel for profile-name resolution failures. |
| Create | `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs` | Shared write/log/error chain reused by both subcommands. |
| Create | `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommand.cs` | Parent verb group. |
| Create | `src/Tools/AHKFlowApp.CLI/Commands/Downloads/AhkDownloadCommand.cs` | `download ahk` action. |
| Create | `src/Tools/AHKFlowApp.CLI/Commands/Downloads/ZipDownloadCommand.cs` | `download zip` action. |
| Modify | `src/Tools/AHKFlowApp.CLI/Program.cs` | Register `IDownloadsApiClient`, `BinaryStdout`, `WorkingDirectory`. |
| Modify | `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs` | Add `DownloadCommand.Build(services)` to root subcommands. |
| Create | `tests/AHKFlowApp.CLI.Tests/Services/BinaryStdoutTests.cs` | Trivial round-trip test. |
| Create | `tests/AHKFlowApp.CLI.Tests/Services/WorkingDirectoryTests.cs` | Trivial round-trip test. |
| Create | `tests/AHKFlowApp.CLI.Tests/Output/DownloadDestinationTests.cs` | `Resolve` + `WriteAsync` table. |
| Create | `tests/AHKFlowApp.CLI.Tests/Services/DownloadsApiClientTests.cs` | Content-Disposition parsing, `SafeFileName` fallbacks, `ApiException` mapping. |
| Modify | `tests/AHKFlowApp.CLI.Tests/Infrastructure/CliTestHost.cs` | Register `IDownloadsApiClient` + the two seams. |
| Create | `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/AhkDownloadCommandTests.cs` | Argument parsing + error mapping using `WithFakes`. |
| Create | `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/ZipDownloadCommandTests.cs` | Argument parsing + error mapping using `WithFakes`. |
| Create | `tests/AHKFlowApp.CLI.Tests/Integration/DownloadCliIntegrationTests.cs` | End-to-end through `WebApplicationFactory<Program>`. |
| Modify | `.claude/backlog/028-cli-download-command.md` | Add zip AC line; refine out-of-scope wording. |

Each task below produces a working compile + green test run, then commits.

---

## Task 1: Inject-friendly seams (`BinaryStdout`, `WorkingDirectory`)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/BinaryStdout.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/WorkingDirectory.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/BinaryStdoutTests.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/WorkingDirectoryTests.cs`

- [ ] **Step 1: Write the failing tests.**

`tests/AHKFlowApp.CLI.Tests/Services/BinaryStdoutTests.cs`:

```csharp
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class BinaryStdoutTests
{
    [Fact]
    public void Open_WithCustomFactory_ReturnsFactoryStream()
    {
        using MemoryStream ms = new();
        BinaryStdout sut = new(() => ms);

        Stream result = sut.Open();

        result.Should().BeSameAs(ms);
    }

    [Fact]
    public void Open_DefaultFactory_ReturnsConsoleStdout()
    {
        BinaryStdout sut = new();

        Stream result = sut.Open();

        result.Should().NotBeNull();
        result.CanWrite.Should().BeTrue();
    }
}
```

`tests/AHKFlowApp.CLI.Tests/Services/WorkingDirectoryTests.cs`:

```csharp
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class WorkingDirectoryTests
{
    [Fact]
    public void Get_WithCustomFactory_ReturnsFactoryValue()
    {
        WorkingDirectory sut = new(() => "/tmp/test");

        sut.Get().Should().Be("/tmp/test");
    }

    [Fact]
    public void Get_DefaultFactory_ReturnsEnvironmentCurrentDirectory()
    {
        WorkingDirectory sut = new();

        sut.Get().Should().Be(Environment.CurrentDirectory);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~BinaryStdoutTests|FullyQualifiedName~WorkingDirectoryTests"
```

Expected: build error — `BinaryStdout` / `WorkingDirectory` not found.

- [ ] **Step 3: Create `BinaryStdout`.**

`src/Tools/AHKFlowApp.CLI/Services/BinaryStdout.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public sealed class BinaryStdout(Func<Stream>? factory = null)
{
    private readonly Func<Stream> _factory = factory ?? Console.OpenStandardOutput;

    public Stream Open() => _factory();
}
```

- [ ] **Step 4: Create `WorkingDirectory`.**

`src/Tools/AHKFlowApp.CLI/Services/WorkingDirectory.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public sealed class WorkingDirectory(Func<string>? factory = null)
{
    private readonly Func<string> _factory = factory ?? (() => Environment.CurrentDirectory);

    public string Get() => _factory();
}
```

- [ ] **Step 5: Run tests to verify they pass.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~BinaryStdoutTests|FullyQualifiedName~WorkingDirectoryTests"
```

Expected: 4 passed.

- [ ] **Step 6: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Services/BinaryStdout.cs src/Tools/AHKFlowApp.CLI/Services/WorkingDirectory.cs tests/AHKFlowApp.CLI.Tests/Services/BinaryStdoutTests.cs tests/AHKFlowApp.CLI.Tests/Services/WorkingDirectoryTests.cs
git commit -m "feat(028): add BinaryStdout and WorkingDirectory DI seams"
```

---

## Task 2: `DownloadTarget` union + `DownloadDestination.Resolve`

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Output/DownloadDestination.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Output/DownloadDestinationTests.cs`

- [ ] **Step 1: Write the failing test for `Resolve`.**

`tests/AHKFlowApp.CLI.Tests/Output/DownloadDestinationTests.cs`:

```csharp
using AHKFlowApp.CLI.Output;
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
        ((DownloadTarget.FileTarget)t).Path.Should().Be(Path.Combine(newDir, "foo.ahk"));
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
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadDestinationTests"
```

Expected: build error — `DownloadTarget` / `DownloadDestination` undefined.

- [ ] **Step 3: Create `DownloadDestination.cs` with `DownloadTarget` and `Resolve`.**

`src/Tools/AHKFlowApp.CLI/Output/DownloadDestination.cs`:

```csharp
namespace AHKFlowApp.CLI.Output;

public abstract record DownloadTarget
{
    public sealed record StdoutTarget : DownloadTarget;
    public sealed record FileTarget(string Path) : DownloadTarget;

    public static readonly DownloadTarget Stdout = new StdoutTarget();
    public static DownloadTarget File(string path) => new FileTarget(path);
}

public static class DownloadDestination
{
    public static DownloadTarget Resolve(string? optionValue, string serverFileName, string baseDirectory)
    {
        if (optionValue is null)
            return DownloadTarget.File(Path.Combine(baseDirectory, serverFileName));

        if (optionValue == "-")
            return DownloadTarget.Stdout;

        bool endsWithSep = Path.EndsInDirectorySeparator(optionValue);
        string normalized = Path.IsPathRooted(optionValue)
            ? optionValue
            : Path.GetFullPath(optionValue, baseDirectory);

        if (endsWithSep || Directory.Exists(normalized))
            return DownloadTarget.File(Path.Combine(normalized, serverFileName));

        return DownloadTarget.File(normalized);
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadDestinationTests"
```

Expected: 7 passed.

- [ ] **Step 5: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Output/DownloadDestination.cs tests/AHKFlowApp.CLI.Tests/Output/DownloadDestinationTests.cs
git commit -m "feat(028): add DownloadTarget union and DownloadDestination.Resolve"
```

---

## Task 3: `DownloadDestination.WriteAsync`

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Output/DownloadDestination.cs`
- Modify: `tests/AHKFlowApp.CLI.Tests/Output/DownloadDestinationTests.cs`

- [ ] **Step 1: Add the failing tests.**

Append to `DownloadDestinationTests.cs` (inside the existing class):

```csharp
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
```

Add `using AHKFlowApp.CLI.Services;` near the top of the file.

- [ ] **Step 2: Run the tests to verify they fail.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadDestinationTests"
```

Expected: build error — `WriteAsync` undefined.

- [ ] **Step 3: Add `WriteAsync` to `DownloadDestination.cs`.**

Add `using AHKFlowApp.CLI.Services;` to the file. Append inside the `DownloadDestination` static class:

```csharp
public static async Task WriteAsync(
    DownloadTarget target, byte[] bytes, BinaryStdout binaryStdout, CancellationToken ct)
{
    switch (target)
    {
        case DownloadTarget.StdoutTarget:
        {
            Stream stdout = binaryStdout.Open();
            await stdout.WriteAsync(bytes, ct);
            await stdout.FlushAsync(ct);
            break;
        }
        case DownloadTarget.FileTarget file:
        {
            string? dir = Path.GetDirectoryName(file.Path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            await File.WriteAllBytesAsync(file.Path, bytes, ct);
            break;
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadDestinationTests"
```

Expected: 10 passed.

- [ ] **Step 5: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Output/DownloadDestination.cs tests/AHKFlowApp.CLI.Tests/Output/DownloadDestinationTests.cs
git commit -m "feat(028): add DownloadDestination.WriteAsync (file + injected stdout)"
```

---

## Task 4: `DownloadsApiClient` (both methods + `SafeFileName` + tests)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/DownloadsApiClient.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/DownloadsApiClientTests.cs`

The `IDownloadsApiClient` interface and `DownloadResult` record already exist (see `Services/IDownloadsApiClient.cs` — leave unchanged).

- [ ] **Step 1: Write the failing tests.**

`tests/AHKFlowApp.CLI.Tests/Services/DownloadsApiClientTests.cs`:

```csharp
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
        Guid id = Guid.NewGuid();
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
    [InlineData("with\0nul.ahk")]
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

        Func<Task> act = () => sut.GetProfileScriptAsync(Guid.NewGuid(), CancellationToken.None);

        ApiException ex = (await act.Should().ThrowAsync<ApiException>()).Which;
        ex.StatusCode.Should().Be(404);
        ex.Body.Should().Be("not your profile");
    }

    [Fact]
    public async Task GetProfileScript_HitsExpectedRoute()
    {
        Guid id = Guid.NewGuid();
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
```

- [ ] **Step 2: Run the tests to verify they fail.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadsApiClientTests"
```

Expected: build error — `DownloadsApiClient` not defined.

- [ ] **Step 3: Create `DownloadsApiClient.cs`.**

`src/Tools/AHKFlowApp.CLI/Services/DownloadsApiClient.cs`:

```csharp
using System.Net.Http.Headers;

namespace AHKFlowApp.CLI.Services;

public sealed class DownloadsApiClient(HttpClient http) : IDownloadsApiClient
{
    private const string DefaultProfileFileName = "profile.ahk";
    private const string DefaultZipFileName = "ahkflow_scripts.zip";
    private const string DefaultProfileContentType = "text/plain";
    private const string DefaultZipContentType = "application/zip";

    public async Task<DownloadResult> GetProfileScriptAsync(Guid profileId, CancellationToken ct)
    {
        using HttpResponseMessage response = await http.GetAsync($"api/v1/downloads/{profileId}", ct);
        return await ReadAsync(response, DefaultProfileFileName, DefaultProfileContentType, ct);
    }

    public async Task<DownloadResult> GetAllProfileScriptsZipAsync(CancellationToken ct)
    {
        using HttpResponseMessage response = await http.GetAsync("api/v1/downloads/zip", ct);
        return await ReadAsync(response, DefaultZipFileName, DefaultZipContentType, ct);
    }

    private static async Task<DownloadResult> ReadAsync(
        HttpResponseMessage response, string fallbackName, string fallbackContentType, CancellationToken ct)
    {
        if (!response.IsSuccessStatusCode)
        {
            string body = await response.Content.ReadAsStringAsync(ct);
            throw new ApiException((int)response.StatusCode, body);
        }

        byte[] bytes = await response.Content.ReadAsByteArrayAsync(ct);
        string raw = ExtractFileName(response.Content.Headers.ContentDisposition);
        string fileName = SafeFileName(raw, fallbackName);
        string contentType = response.Content.Headers.ContentType?.ToString() ?? fallbackContentType;
        return new DownloadResult(bytes, fileName, contentType);
    }

    private static string ExtractFileName(ContentDispositionHeaderValue? cd)
    {
        if (cd is null) return string.Empty;
        string? candidate = cd.FileNameStar ?? cd.FileName;
        if (string.IsNullOrWhiteSpace(candidate)) return string.Empty;
        return candidate.Trim().Trim('"');
    }

    private static string SafeFileName(string raw, string fallback)
    {
        if (string.IsNullOrWhiteSpace(raw)) return fallback;
        if (raw.Contains('/') || raw.Contains('\\')) return fallback;
        if (Path.IsPathRooted(raw)) return fallback;
        if (raw.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return fallback;
        if (Path.GetFileName(raw) != raw) return fallback;
        return raw;
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadsApiClientTests"
```

Expected: all (~13) tests pass.

- [ ] **Step 5: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Services/DownloadsApiClient.cs tests/AHKFlowApp.CLI.Tests/Services/DownloadsApiClientTests.cs
git commit -m "feat(028): add DownloadsApiClient with sanitised Content-Disposition parsing"
```

---

## Task 5: Extend `CliTestHost` with downloads + seams

**Files:**
- Modify: `tests/AHKFlowApp.CLI.Tests/Infrastructure/CliTestHost.cs`

This task only touches test infrastructure. No standalone tests; downstream Tasks 6–9 exercise it.

- [ ] **Step 1: Replace `CliTestHost` with the extended version.**

Read the existing file at `tests/AHKFlowApp.CLI.Tests/Infrastructure/CliTestHost.cs` and rewrite as:

```csharp
using AHKFlowApp.API;
using AHKFlowApp.CLI.Services;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Tests.Infrastructure;

internal static class CliTestHost
{
    public static IServiceProvider WithFakes(
        IHotstringsApiClient hotstrings,
        IProfilesApiClient profiles,
        IDownloadsApiClient? downloads = null,
        IAuthTokenProvider? auth = null,
        BinaryStdout? binaryStdout = null,
        WorkingDirectory? workingDirectory = null)
    {
        ServiceCollection services = new();
        services.AddSingleton(hotstrings);
        services.AddSingleton(profiles);
        if (downloads is not null) services.AddSingleton(downloads);
        services.AddSingleton(auth ?? new StubAuthTokenProvider("test-token"));
        services.AddSingleton(binaryStdout ?? new BinaryStdout(() => new MemoryStream()));
        services.AddSingleton(workingDirectory ?? new WorkingDirectory(() => Path.GetTempPath()));
        return services.BuildServiceProvider();
    }

    public static IServiceProvider WithFactory(
        WebApplicationFactory<Program> factory,
        string? token = "test-token",
        RequestCounter? counter = null,
        Stream? stdoutSink = null,
        string? baseDirectory = null)
    {
        ServiceCollection services = new();
        services.AddSingleton<IAuthTokenProvider>(new StubAuthTokenProvider(token));
        services.AddTransient<BearerTokenHandler>();

        IHttpClientBuilder hsBuilder = services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();
        if (counter is not null) hsBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));

        IHttpClientBuilder pBuilder = services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();
        if (counter is not null) pBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));

        IHttpClientBuilder dBuilder = services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();
        if (counter is not null) dBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));

        services.AddSingleton(new BinaryStdout(stdoutSink is null ? () => new MemoryStream() : () => stdoutSink));
        services.AddSingleton(new WorkingDirectory(() => baseDirectory ?? Path.GetTempPath()));

        return services.BuildServiceProvider();
    }
}
```

- [ ] **Step 2: Confirm the existing CLI test suite still builds and passes.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release
```

Expected: all existing tests still green (no behavioural change for hotstring tests; new optional parameters default to existing behaviour).

- [ ] **Step 3: Commit.**

```
git add tests/AHKFlowApp.CLI.Tests/Infrastructure/CliTestHost.cs
git commit -m "test(028): extend CliTestHost with downloads client + binary stdout + cwd seams"
```

---

## Task 6: `AhkDownloadCommand` (+ shared `DownloadCommandRunner`)

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Exceptions/ProfileNotFoundException.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Downloads/AhkDownloadCommand.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/AhkDownloadCommandTests.cs`

The shared runner handles the write/log/error chain for both ahk and zip subcommands; `ProfileNotFoundException` is a tiny sentinel that lets profile resolution flow through the same catch chain as exit 2.

- [ ] **Step 1: Write the failing tests.**

`tests/AHKFlowApp.CLI.Tests/Commands/Downloads/AhkDownloadCommandTests.cs`:

```csharp
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
        Guid pid = Guid.NewGuid();
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
        Guid pid = Guid.NewGuid();
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
            .Throws(new NotAuthenticatedException(
                "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token."));

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "x"], downloads, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain("Not signed in");
    }

    [Fact]
    public async Task ApiException401_Exit3()
    {
        Guid pid = Guid.NewGuid();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns([new ProfileSummary(pid, "work")]);

        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetProfileScriptAsync(pid, Arg.Any<CancellationToken>())
            .Throws(new ApiException(401, "unauth"));

        (int exit, string _, string stderr) = await RunAsync(
            ["--profile", "work"], downloads, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain("Not signed in");
    }

    [Fact]
    public async Task ApiException404_Exit2()
    {
        Guid pid = Guid.NewGuid();
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
        Guid pid = Guid.NewGuid();
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
    public async Task ProfileNameCaseInsensitive()
    {
        Guid pid = Guid.NewGuid();
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
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~AhkDownloadCommandTests"
```

Expected: build error — `AhkDownloadCommand` undefined.

- [ ] **Step 3: Create `ProfileNotFoundException`.**

`src/Tools/AHKFlowApp.CLI/Exceptions/ProfileNotFoundException.cs`:

```csharp
namespace AHKFlowApp.CLI.Exceptions;

internal sealed class ProfileNotFoundException(string profileName, string availableNames)
    : Exception($"Profile '{profileName}' not found. Available: {availableNames}");
```

- [ ] **Step 4: Create `DownloadCommandRunner`.**

`src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Output;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Downloads;

internal static class DownloadCommandRunner
{
    public static async Task<int> RunAsync(
        ParseResult parse,
        IServiceProvider services,
        string? outputOption,
        Func<CancellationToken, Task<DownloadResult>> fetch,
        CancellationToken ct)
    {
        TextWriter stdout = parse.InvocationConfiguration.Output;
        TextWriter stderr = parse.InvocationConfiguration.Error;
        BinaryStdout binaryStdout = services.GetRequiredService<BinaryStdout>();
        WorkingDirectory workingDir = services.GetRequiredService<WorkingDirectory>();

        try
        {
            DownloadResult result = await fetch(ct);
            DownloadTarget target = DownloadDestination.Resolve(outputOption, result.FileName, workingDir.Get());
            await DownloadDestination.WriteAsync(target, result.Bytes, binaryStdout, ct);

            if (target is DownloadTarget.FileTarget file)
                await stdout.WriteLineAsync($"Wrote {file.Path} ({result.Bytes.Length} bytes)");

            return 0;
        }
        catch (ProfileNotFoundException ex)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 2;
        }
        catch (NotAuthenticatedException ex)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 3;
        }
        catch (ApiException ex) when (ex.StatusCode == 401)
        {
            await stderr.WriteLineAsync(
                "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token.");
            return 3;
        }
        catch (ApiException ex) when (ex.StatusCode is 400 or 404 or 409)
        {
            await stderr.WriteLineAsync(ex.Body ?? ex.Message);
            return 2;
        }
        catch (ApiException ex)
        {
            await stderr.WriteLineAsync(ex.Body ?? $"Server error ({ex.StatusCode}).");
            return 1;
        }
        catch (HttpRequestException ex)
        {
            await stderr.WriteLineAsync(ex.Message);
            return 1;
        }
    }
}
```

- [ ] **Step 5: Create `AhkDownloadCommand.cs`.**

`src/Tools/AHKFlowApp.CLI/Commands/Downloads/AhkDownloadCommand.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Downloads;

public static class AhkDownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string> profile = new("--profile", "-p")
        {
            Description = "Profile name (case-insensitive).",
            Required = true,
        };
        Option<string?> output = new("--output", "-o")
        {
            Description = "Output path. Default: server-named file in current directory. '-' writes to stdout.",
        };

        Command cmd = new("ahk", "Download the generated .ahk for a single profile.") { profile, output };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            IDownloadsApiClient downloads = services.GetRequiredService<IDownloadsApiClient>();
            IProfilesApiClient profilesClient = services.GetRequiredService<IProfilesApiClient>();

            string profileName = parse.GetValue(profile)!;
            string? outputOption = parse.GetValue(output);

            return await DownloadCommandRunner.RunAsync(
                parse, services, outputOption,
                async token =>
                {
                    IReadOnlyList<ProfileSummary> all = await profilesClient.ListAsync(token);
                    ProfileSummary? match = all.FirstOrDefault(p =>
                        string.Equals(p.Name, profileName, StringComparison.OrdinalIgnoreCase));
                    if (match is null)
                    {
                        string available = string.Join(", ", all.Select(a => a.Name));
                        throw new ProfileNotFoundException(profileName, available);
                    }
                    return await downloads.GetProfileScriptAsync(match.Id, token);
                },
                ct);
        });

        return cmd;
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~AhkDownloadCommandTests"
```

Expected: all 8 tests pass.

- [ ] **Step 7: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Exceptions/ProfileNotFoundException.cs src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs src/Tools/AHKFlowApp.CLI/Commands/Downloads/AhkDownloadCommand.cs tests/AHKFlowApp.CLI.Tests/Commands/Downloads/AhkDownloadCommandTests.cs
git commit -m "feat(028): add 'ahkflow download ahk' subcommand and shared runner"
```

---

## Task 7: `ZipDownloadCommand`

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Downloads/ZipDownloadCommand.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/ZipDownloadCommandTests.cs`

- [ ] **Step 1: Write the failing tests.**

`tests/AHKFlowApp.CLI.Tests/Commands/Downloads/ZipDownloadCommandTests.cs`:

```csharp
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
            .Throws(new NotAuthenticatedException(
                "Not signed in. Set AHKFLOW_TOKEN environment variable to a bearer token."));

        (int exit, string _, string stderr) = await RunAsync([], downloads);

        exit.Should().Be(3);
        stderr.Should().Contain("Not signed in");
    }

    [Fact]
    public async Task ApiException401_Exit3()
    {
        IDownloadsApiClient downloads = Substitute.For<IDownloadsApiClient>();
        downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Throws(new ApiException(401, "unauth"));

        (int exit, string _, string stderr) = await RunAsync([], downloads);

        exit.Should().Be(3);
        stderr.Should().Contain("Not signed in");
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
```

- [ ] **Step 2: Run the tests to verify they fail.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~ZipDownloadCommandTests"
```

Expected: build error — `ZipDownloadCommand` undefined.

- [ ] **Step 3: Create `ZipDownloadCommand.cs`.**

`src/Tools/AHKFlowApp.CLI/Commands/Downloads/ZipDownloadCommand.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Downloads;

public static class ZipDownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Option<string?> output = new("--output", "-o")
        {
            Description = "Output path. Default: ahkflow_scripts.zip in current directory. '-' writes to stdout.",
        };

        Command cmd = new("zip", "Download a zip of every profile's generated .ahk.") { output };

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            IDownloadsApiClient downloads = services.GetRequiredService<IDownloadsApiClient>();
            string? outputOption = parse.GetValue(output);

            return await DownloadCommandRunner.RunAsync(
                parse, services, outputOption,
                token => downloads.GetAllProfileScriptsZipAsync(token),
                ct);
        });

        return cmd;
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~ZipDownloadCommandTests"
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Commands/Downloads/ZipDownloadCommand.cs tests/AHKFlowApp.CLI.Tests/Commands/Downloads/ZipDownloadCommandTests.cs
git commit -m "feat(028): add 'ahkflow download zip' subcommand"
```

---

## Task 8: Wire `DownloadCommand` parent + `RootCli` + `Program.cs` DI

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommand.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`

- [ ] **Step 1: Create the parent `DownloadCommand`.**

`src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommand.cs`:

```csharp
using System.CommandLine;

namespace AHKFlowApp.CLI.Commands.Downloads;

public static class DownloadCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("download", "Download generated AutoHotkey scripts.")
        {
            AhkDownloadCommand.Build(services),
            ZipDownloadCommand.Build(services),
        };
        return cmd;
    }
}
```

- [ ] **Step 2: Wire `DownloadCommand` into `RootCli.cs`.**

Edit `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`. Change to:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Commands.Downloads;
using AHKFlowApp.CLI.Commands.Hotstrings;

namespace AHKFlowApp.CLI.Commands;

public static class RootCli
{
    public static readonly Option<bool> VerboseOption = new("--verbose", "-v")
    {
        Description = "Enable Information-level logs to stderr.",
        Recursive = true,
    };

    public static RootCommand Build(IServiceProvider services)
    {
        RootCommand root = new("ahkflow - AHKFlowApp CLI")
        {
            VerboseOption,
            HotstringCommand.Build(services),
            DownloadCommand.Build(services),
        };
        // Subcommands wired in subsequent phases:
        //   root.Subcommands.Add(LoginCommand.Build(services));
        //   root.Subcommands.Add(LogoutCommand.Build(services));
        return root;
    }
}
```

- [ ] **Step 3: Register `IDownloadsApiClient`, `BinaryStdout`, `WorkingDirectory` in `Program.cs`.**

Edit `src/Tools/AHKFlowApp.CLI/Program.cs`. Replace the line `// IDownloadsApiClient registration lands with backlog 028.` with:

```csharp
builder.Services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

builder.Services.AddSingleton<BinaryStdout>();
builder.Services.AddSingleton<WorkingDirectory>();
```

- [ ] **Step 4: Verify the help text exposes the new commands and the build is green.**

```
dotnet build src/Tools/AHKFlowApp.CLI --configuration Release
dotnet run --project src/Tools/AHKFlowApp.CLI -- download --help
```

Expected: build succeeds; help output lists `ahk` and `zip` subcommands under `download`.

- [ ] **Step 5: Run the full CLI test suite — sanity check.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release
```

Expected: all tests still green.

- [ ] **Step 6: Commit.**

```
git add src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommand.cs src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs src/Tools/AHKFlowApp.CLI/Program.cs
git commit -m "feat(028): wire DownloadCommand into RootCli and register DI"
```

---

## Task 9: Integration tests via `WebApplicationFactory<Program>`

**Files:**
- Create: `tests/AHKFlowApp.CLI.Tests/Integration/DownloadCliIntegrationTests.cs`

- [ ] **Step 1: Write the integration tests.**

`tests/AHKFlowApp.CLI.Tests/Integration/DownloadCliIntegrationTests.cs`:

```csharp
using System.CommandLine;
using System.IO.Compression;
using System.Text;
using AHKFlowApp.API;
using AHKFlowApp.CLI.Commands.Downloads;
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

    private async Task<Profile> SeedProfileAsync(string name)
    {
        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Profile p = new ProfileBuilder().WithOwner(_testUserOid).WithName(name).Build();
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

    private static async Task<string> ReadAllEntriesAsync(ZipArchive zip)
    {
        StringBuilder sb = new();
        foreach (ZipArchiveEntry entry in zip.Entries)
        {
            await using Stream s = entry.Open();
            using StreamReader reader = new(s, Encoding.UTF8);
            sb.AppendLine(await reader.ReadToEndAsync());
        }
        return sb.ToString();
    }

    [Fact]
    public async Task Auth_TokenUnset_Exit3()
    {
        await SeedProfileAsync("work");

        (int exit, string _, string stderr, byte[] _) = await RunAsync(
            ["download", "ahk", "--profile", "work"], token: null);

        exit.Should().Be(3);
        stderr.Should().Contain("Not signed in");
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
}
```

- [ ] **Step 2: Run the integration tests.**

```
dotnet test tests/AHKFlowApp.CLI.Tests --filter "FullyQualifiedName~DownloadCliIntegrationTests" --configuration Release
```

Expected: 10 tests pass. (Container startup may take 30–60s on first run.)

- [ ] **Step 3: Commit.**

```
git add tests/AHKFlowApp.CLI.Tests/Integration/DownloadCliIntegrationTests.cs
git commit -m "test(028): add CLI download integration tests against WebApplicationFactory"
```

---

## Task 10: Update backlog item

**Files:**
- Modify: `.claude/backlog/028-cli-download-command.md`

- [ ] **Step 1: Add the zip AC and refine out-of-scope wording.**

In `.claude/backlog/028-cli-download-command.md`:

Within the `## Acceptance criteria` block, after the line:
```
- [ ] `ahkflow download ahk --profile <name>` downloads the script.
```
add:
```
- [ ] `ahkflow download zip` downloads a zip of all the user's profile scripts to cwd (or `-o`).
```

Replace the existing `## Out of scope` line:
```
- Downloading additional artifacts.
```
with:
```
- Downloading artifacts other than per-profile `.ahk` and the all-profiles zip (e.g., compiled `.exe`, signed bundles).
```

- [ ] **Step 2: Commit.**

```
git add .claude/backlog/028-cli-download-command.md
git commit -m "docs(028): add zip AC and refine out-of-scope wording"
```

---

## Task 11: Final verify (full repo build, tests, formatting)

**Files:** none.

- [ ] **Step 1: Restore + build the whole solution.**

```
dotnet restore
dotnet build --configuration Release --no-restore
```

Expected: build succeeds, no warnings introduced.

- [ ] **Step 2: Run the full test suite.**

```
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: every project's tests pass.

- [ ] **Step 3: Run formatter.**

```
dotnet format --verify-no-changes
```

Expected: no diff. If diffs appear, run `dotnet format`, review, and amend a follow-up commit.

- [ ] **Step 4: Push the branch.**

```
git push -u origin feature/028-cli-download-command
```

- [ ] **Step 5: Write the PR body to a temp file (PowerShell-safe, avoids heredoc).**

Use the Write tool to create `pr-body-028.md` (in the repo root or temp dir) with:

```markdown
## Summary
- `ahkflow download ahk --profile <name>` and `ahkflow download zip` write generated scripts to a path or stdout.
- Defaults to server-named file in cwd; `-o <path>` overrides; `-o -` writes raw bytes to stdout.
- Sanitises `Content-Disposition` filenames at the API client boundary; injectable `BinaryStdout` and `WorkingDirectory` seams keep tests off `Console` and process cwd.

## Test plan
- [x] `dotnet build --configuration Release`
- [x] `dotnet test --configuration Release` (all green)
- [x] `dotnet format --verify-no-changes`
- [x] `dotnet run --project src/Tools/AHKFlowApp.CLI -- download --help` shows both subcommands
```

- [ ] **Step 6: Open the PR using `--body-file`.**

```
gh pr create --title "feat(028): CLI download command (ahk + zip)" --body-file pr-body-028.md
```

Capture the PR URL/number from the command's output (e.g. `https://github.com/.../pull/123` → number 123).

- [ ] **Step 7: Delete the temp body file.**

```
git clean -f pr-body-028.md
```

(Or just `Remove-Item pr-body-028.md` — file is gitignored by virtue of not being added.)

- [ ] **Step 8: Mark ACs and add the completion line with the real PR number.**

In `.claude/backlog/028-cli-download-command.md`: tick every `- [ ]` in `## Acceptance criteria` to `- [x]`, then append (replace `<N>` with the real PR number captured in Step 6):

```

---

**Completed:** 2026-05-09 (PR #<N>)
```

- [ ] **Step 9: Commit and push the AC checkmarks.**

```
git add .claude/backlog/028-cli-download-command.md
git commit -m "docs(028): mark acceptance criteria complete"
git push
```

The follow-up commit attaches itself to the open PR automatically.

(Skip Steps 4–9 if the user wants to defer the PR.)

---

## Self-review notes

The plan covers every spec section:

- **Architecture / file structure** → Tasks 1–9.
- **Decisions 1 (mirror 018), 2 (subcommands), 3 (interface stays)** → Task 6 / 7 / 8 follow the same pattern as the existing 018 commands.
- **Decision 4 (sanitised filename)** → Task 4 adds `SafeFileName` + 5 fallback test cases.
- **Decision 5 (Resolve helper + base dir)** → Task 2; Task 6 / 7 use `WorkingDirectory.Get()` not `Environment.CurrentDirectory`.
- **Decision 6 (BinaryStdout seam)** → Task 1 + Task 3 + tests asserting raw bytes captured.
- **Decision 7 (silent overwrite)** → Task 3 explicit overwrite test + Task 9 `Overwrite_Silent` integration test.
- **Decision 8 (profile name resolution)** → Task 6 uses `IProfilesApiClient.ListAsync`.
- **Decision 9 (exit codes)** → Task 6 introduces shared `DownloadCommandRunner` (mirrors 018's chain plus `ProfileNotFoundException`); Task 7 tests cover 401/404/500 against the runner.
- **Output handling table** → Task 2 (5 Resolve tests) + Task 9 trailing-sep integration test.
- **API client + DI registration** → Tasks 4 + 8.
- **Errors & exit codes** → Task 6 / 7 unit tests.
- **Testing matrix** → Tasks 6 / 7 / 9.
- **Backlog AC update** → Task 10.

No placeholders. All test code is complete. All commands include expected output.
