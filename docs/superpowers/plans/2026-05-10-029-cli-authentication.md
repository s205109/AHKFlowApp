# CLI Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship backlog 029 by replacing temporary `AHKFLOW_TOKEN` auth with MSAL.NET device-code login/logout and cached bearer tokens for all CLI API calls.

**Architecture:** Keep the existing `IAuthTokenProvider` contract and `BearerTokenHandler` pipeline. Add auth commands under `Commands/Auth`, a narrow device-code prompt writer, lazy auth configuration validation, and an `MsalDeviceCodeTokenProvider` registered by `Program.cs`. Update the Entra setup script to make the existing app registration usable as a public client for device-code flow.

**Tech Stack:** .NET 10, System.CommandLine, Microsoft.Identity.Client, Microsoft.Identity.Client.Extensions.Msal, Microsoft.Extensions.Hosting/DI, xUnit, FluentAssertions, NSubstitute, PowerShell 5.1.

---

## File Structure

Create:

- `src/Tools/AHKFlowApp.CLI/Commands/Auth/LoginCommand.cs` - `ahkflow login` command and exit-code mapping.
- `src/Tools/AHKFlowApp.CLI/Commands/Auth/LogoutCommand.cs` - `ahkflow logout` command.
- `src/Tools/AHKFlowApp.CLI/Services/AuthMessages.cs` - shared CLI auth messages.
- `src/Tools/AHKFlowApp.CLI/Exceptions/AuthConfigurationException.cs` - concise invalid auth config failure.
- `src/Tools/AHKFlowApp.CLI/Services/DeviceCodePrompt.cs` - prompt DTO.
- `src/Tools/AHKFlowApp.CLI/Services/IDeviceCodePromptWriter.cs` - prompt output seam.
- `src/Tools/AHKFlowApp.CLI/Services/ConsoleErrorDeviceCodePromptWriter.cs` - writes device-code challenge to stderr.
- `src/Tools/AHKFlowApp.CLI/Services/IAuthCachePathProvider.cs` - cache path seam for production and isolated tests.
- `src/Tools/AHKFlowApp.CLI/Services/LocalAppDataAuthCachePathProvider.cs` - local application data cache path.
- `src/Tools/AHKFlowApp.CLI/Services/MsalDeviceCodeTokenProvider.cs` - lazy MSAL public-client provider and cache wiring.
- `tests/AHKFlowApp.CLI.Tests/Commands/Auth/LoginCommandTests.cs` - command behavior with fake auth provider.
- `tests/AHKFlowApp.CLI.Tests/Commands/Auth/LogoutCommandTests.cs` - command behavior with fake auth provider.
- `tests/AHKFlowApp.CLI.Tests/Services/ConsoleErrorDeviceCodePromptWriterTests.cs` - stderr prompt formatting.
- `tests/AHKFlowApp.CLI.Tests/Services/MsalDeviceCodeTokenProviderTests.cs` - lazy config and no-account behavior without a real tenant.

Modify:

- `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` - add MSAL package references through `dotnet add package`.
- `Directory.Packages.props` - updated by `dotnet add package` because CPM is enabled.
- `src/Tools/AHKFlowApp.CLI/Program.cs` - replace env-var auth provider registration with MSAL provider and prompt writer.
- `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs` - wire login/logout into root command.
- `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs` - update 401 message.
- `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/NewHotstringCommand.cs` - update 401 message.
- `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs` - update 401 message.
- `tests/AHKFlowApp.CLI.Tests/Infrastructure/StubAuthTokenProvider.cs` - update unauthenticated test message.
- `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/AhkDownloadCommandTests.cs` - assert new 401 and auth messages.
- `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/ZipDownloadCommandTests.cs` - assert new 401 and auth messages.
- `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/NewHotstringCommandTests.cs` - assert new 401 and auth messages.
- `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs` - assert new 401 message.
- `src/Tools/AHKFlowApp.CLI/Services/EnvVarAuthTokenProvider.cs` - delete temporary env-var auth provider after MSAL registration is in place.
- `tests/AHKFlowApp.CLI.Tests/Services/EnvVarAuthTokenProviderTests.cs` - delete tests for temporary env-var auth provider.
- `scripts/setup-entra-app.ps1` - add public-client redirect URI and fallback public-client flag.
- `docs/architecture/authentication.md` - replace "deferred" CLI section with shipped design.
- `.claude/backlog/029-cli-authentication.md` - mark acceptance criteria complete after implementation.

---

## Task 1: Add MSAL Packages

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`
- Modify: `Directory.Packages.props`

- [ ] **Step 1: Add MSAL packages through dotnet CLI**

Run:

```powershell
dotnet add src/Tools/AHKFlowApp.CLI package Microsoft.Identity.Client
dotnet add src/Tools/AHKFlowApp.CLI package Microsoft.Identity.Client.Extensions.Msal
```

Expected:

- `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` contains package references without `Version=`.
- `Directory.Packages.props` contains the resolved stable package versions.

- [ ] **Step 2: Build CLI project**

Run:

```powershell
dotnet build src/Tools/AHKFlowApp.CLI --configuration Release
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```powershell
git add src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj Directory.Packages.props
git commit -m "chore(029): add MSAL CLI packages"
```

---

## Task 2: Add Shared Auth Messages and Device-Code Prompt Writer

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/AuthMessages.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/DeviceCodePrompt.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/IDeviceCodePromptWriter.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/ConsoleErrorDeviceCodePromptWriter.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/ConsoleErrorDeviceCodePromptWriterTests.cs`

- [ ] **Step 1: Write the failing prompt writer test**

Create `tests/AHKFlowApp.CLI.Tests/Services/ConsoleErrorDeviceCodePromptWriterTests.cs`:

```csharp
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class ConsoleErrorDeviceCodePromptWriterTests
{
    [Fact]
    public async Task WriteAsync_WritesVerificationUrlAndUserCodeToError()
    {
        using StringWriter stderr = new();
        var sut = new ConsoleErrorDeviceCodePromptWriter(() => stderr);

        await sut.WriteAsync(
            new DeviceCodePrompt(
                "https://microsoft.com/devicelogin",
                "ABC-123",
                "Open the page and enter the code."),
            CancellationToken.None);

        string output = stderr.ToString();
        output.Should().Contain("https://microsoft.com/devicelogin");
        output.Should().Contain("ABC-123");
        output.Should().Contain("Open the page and enter the code.");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~ConsoleErrorDeviceCodePromptWriterTests" --verbosity normal
```

Expected: fail because `ConsoleErrorDeviceCodePromptWriter` does not exist.

- [ ] **Step 3: Add auth message and prompt types**

Create `src/Tools/AHKFlowApp.CLI/Services/AuthMessages.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public static class AuthMessages
{
    public const string LoginRequired = "Run 'ahkflow login' first.";
    public const string AuthenticationFailed = "Authentication failed. Run 'ahkflow login'.";
}
```

Create `src/Tools/AHKFlowApp.CLI/Services/DeviceCodePrompt.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public sealed record DeviceCodePrompt(
    string VerificationUrl,
    string UserCode,
    string Message);
```

Create `src/Tools/AHKFlowApp.CLI/Services/IDeviceCodePromptWriter.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public interface IDeviceCodePromptWriter
{
    Task WriteAsync(DeviceCodePrompt prompt, CancellationToken ct);
}
```

Create `src/Tools/AHKFlowApp.CLI/Services/ConsoleErrorDeviceCodePromptWriter.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public sealed class ConsoleErrorDeviceCodePromptWriter(Func<TextWriter>? errorFactory = null)
    : IDeviceCodePromptWriter
{
    private readonly Func<TextWriter> _errorFactory = errorFactory ?? (() => Console.Error);

    public async Task WriteAsync(DeviceCodePrompt prompt, CancellationToken ct)
    {
        TextWriter stderr = _errorFactory();
        await stderr.WriteLineAsync(prompt.Message);
        await stderr.WriteLineAsync($"Verification URL: {prompt.VerificationUrl}");
        await stderr.WriteLineAsync($"Code: {prompt.UserCode}");
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~ConsoleErrorDeviceCodePromptWriterTests" --verbosity normal
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add src/Tools/AHKFlowApp.CLI/Services/AuthMessages.cs src/Tools/AHKFlowApp.CLI/Services/DeviceCodePrompt.cs src/Tools/AHKFlowApp.CLI/Services/IDeviceCodePromptWriter.cs src/Tools/AHKFlowApp.CLI/Services/ConsoleErrorDeviceCodePromptWriter.cs tests/AHKFlowApp.CLI.Tests/Services/ConsoleErrorDeviceCodePromptWriterTests.cs
git commit -m "feat(029): add CLI device-code prompt writer"
```

---

## Task 3: Add Login and Logout Commands

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Auth/LoginCommand.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Commands/Auth/LogoutCommand.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Exceptions/AuthConfigurationException.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Commands/Auth/LoginCommandTests.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Commands/Auth/LogoutCommandTests.cs`

- [ ] **Step 1: Write failing login command tests**

Create `tests/AHKFlowApp.CLI.Tests/Commands/Auth/LoginCommandTests.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Commands.Auth;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Commands.Auth;

public sealed class LoginCommandTests
{
    private static async Task<(int exit, string stdout, string stderr)> RunAsync(
        IAuthTokenProvider auth)
    {
        ServiceCollection services = new();
        services.AddSingleton(auth);
        IServiceProvider provider = services.BuildServiceProvider();

        StringWriter so = new(), se = new();
        RootCommand root = new() { LoginCommand.Build(provider) };
        int exit = await root.Parse(["login"])
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    [Fact]
    public async Task LoginAsync_NewSignIn_PrintsSignedIn()
    {
        IAuthTokenProvider auth = Substitute.For<IAuthTokenProvider>();
        auth.LoginAsync(Arg.Any<CancellationToken>())
            .Returns(new LoginResult("user@example.com", false));

        (int exit, string stdout, string stderr) = await RunAsync(auth);

        exit.Should().Be(0);
        stdout.Should().Contain("Signed in as user@example.com");
        stderr.Should().BeEmpty();
    }

    [Fact]
    public async Task LoginAsync_AlreadySignedIn_PrintsAlreadySignedIn()
    {
        IAuthTokenProvider auth = Substitute.For<IAuthTokenProvider>();
        auth.LoginAsync(Arg.Any<CancellationToken>())
            .Returns(new LoginResult("user@example.com", true));

        (int exit, string stdout, string stderr) = await RunAsync(auth);

        exit.Should().Be(0);
        stdout.Should().Contain("Already signed in as user@example.com");
        stderr.Should().BeEmpty();
    }

    [Fact]
    public async Task LoginAsync_NotAuthenticated_Exit3()
    {
        IAuthTokenProvider auth = Substitute.For<IAuthTokenProvider>();
        auth.LoginAsync(Arg.Any<CancellationToken>())
            .Throws(new NotAuthenticatedException(AuthMessages.LoginRequired));

        (int exit, string stdout, string stderr) = await RunAsync(auth);

        exit.Should().Be(3);
        stdout.Should().BeEmpty();
        stderr.Should().Contain(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task LoginAsync_InvalidConfiguration_Exit1()
    {
        IAuthTokenProvider auth = Substitute.For<IAuthTokenProvider>();
        auth.LoginAsync(Arg.Any<CancellationToken>())
            .Throws(new AuthConfigurationException("ClientId is not configured."));

        (int exit, string stdout, string stderr) = await RunAsync(auth);

        exit.Should().Be(1);
        stdout.Should().BeEmpty();
        stderr.Should().Contain("ClientId is not configured.");
    }
}
```

- [ ] **Step 2: Write failing logout command tests**

Create `tests/AHKFlowApp.CLI.Tests/Commands/Auth/LogoutCommandTests.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Commands.Auth;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Commands.Auth;

public sealed class LogoutCommandTests
{
    private static async Task<(int exit, string stdout, string stderr)> RunAsync(
        IAuthTokenProvider auth)
    {
        ServiceCollection services = new();
        services.AddSingleton(auth);
        IServiceProvider provider = services.BuildServiceProvider();

        StringWriter so = new(), se = new();
        RootCommand root = new() { LogoutCommand.Build(provider) };
        int exit = await root.Parse(["logout"])
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    [Fact]
    public async Task LogoutAsync_Success_PrintsSignedOut()
    {
        IAuthTokenProvider auth = Substitute.For<IAuthTokenProvider>();

        (int exit, string stdout, string stderr) = await RunAsync(auth);

        exit.Should().Be(0);
        stdout.Should().Contain("Signed out");
        stderr.Should().BeEmpty();
        await auth.Received(1).LogoutAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task LogoutAsync_InvalidConfiguration_Exit1()
    {
        IAuthTokenProvider auth = Substitute.For<IAuthTokenProvider>();
        auth.LogoutAsync(Arg.Any<CancellationToken>())
            .Throws(new AuthConfigurationException("TenantId is not configured."));

        (int exit, string stdout, string stderr) = await RunAsync(auth);

        exit.Should().Be(1);
        stdout.Should().BeEmpty();
        stderr.Should().Contain("TenantId is not configured.");
    }
}
```

- [ ] **Step 3: Run command tests to verify they fail**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~Commands.Auth" --verbosity normal
```

Expected: fail because `LoginCommand`, `LogoutCommand`, and `AuthConfigurationException` do not exist.

- [ ] **Step 4: Add auth configuration exception**

Create `src/Tools/AHKFlowApp.CLI/Exceptions/AuthConfigurationException.cs`:

```csharp
namespace AHKFlowApp.CLI.Exceptions;

public sealed class AuthConfigurationException(string message) : Exception(message);
```

- [ ] **Step 5: Add login command**

Create `src/Tools/AHKFlowApp.CLI/Commands/Auth/LoginCommand.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Auth;

public static class LoginCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("login", "Sign in to AHKFlowApp.");

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IAuthTokenProvider auth = services.GetRequiredService<IAuthTokenProvider>();

            try
            {
                LoginResult result = await auth.LoginAsync(ct);
                string prefix = result.WasAlreadySignedIn ? "Already signed in as" : "Signed in as";
                await stdout.WriteLineAsync($"{prefix} {result.Username}");
                return 0;
            }
            catch (NotAuthenticatedException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 3;
            }
            catch (AuthConfigurationException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
            catch (HttpRequestException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 6: Add logout command**

Create `src/Tools/AHKFlowApp.CLI/Commands/Auth/LogoutCommand.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Commands.Auth;

public static class LogoutCommand
{
    public static Command Build(IServiceProvider services)
    {
        Command cmd = new("logout", "Sign out of AHKFlowApp.");

        cmd.SetAction(async (ParseResult parse, CancellationToken ct) =>
        {
            TextWriter stdout = parse.InvocationConfiguration.Output;
            TextWriter stderr = parse.InvocationConfiguration.Error;
            IAuthTokenProvider auth = services.GetRequiredService<IAuthTokenProvider>();

            try
            {
                await auth.LogoutAsync(ct);
                await stdout.WriteLineAsync("Signed out");
                return 0;
            }
            catch (AuthConfigurationException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
            catch (HttpRequestException ex)
            {
                await stderr.WriteLineAsync(ex.Message);
                return 1;
            }
        });

        return cmd;
    }
}
```

- [ ] **Step 7: Wire commands into root CLI**

Modify `src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs`:

```csharp
using System.CommandLine;
using AHKFlowApp.CLI.Commands.Auth;
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
            LoginCommand.Build(services),
            LogoutCommand.Build(services),
            HotstringCommand.Build(services),
            DownloadCommand.Build(services),
        };
        return root;
    }
}
```

- [ ] **Step 8: Run command tests to verify they pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~Commands.Auth" --verbosity normal
```

Expected: pass.

- [ ] **Step 9: Smoke root help includes login/logout**

Run:

```powershell
dotnet run --project src/Tools/AHKFlowApp.CLI -- --help
```

Expected: output includes `login` and `logout`; it must not fail because `ClientId` / `TenantId` are zero GUIDs in `appsettings.json`.

- [ ] **Step 10: Commit**

```powershell
git add src/Tools/AHKFlowApp.CLI/Commands/Auth src/Tools/AHKFlowApp.CLI/Commands/RootCli.cs src/Tools/AHKFlowApp.CLI/Exceptions/AuthConfigurationException.cs tests/AHKFlowApp.CLI.Tests/Commands/Auth
git commit -m "feat(029): add CLI login and logout commands"
```

---

## Task 4: Update Stale Auth Failure Messages in Existing CLI Commands

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/NewHotstringCommand.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs`
- Modify: `tests/AHKFlowApp.CLI.Tests/Infrastructure/StubAuthTokenProvider.cs`
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/AhkDownloadCommandTests.cs`
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/Downloads/ZipDownloadCommandTests.cs`
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/NewHotstringCommandTests.cs`
- Modify: `tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings/ListHotstringCommandTests.cs`

- [ ] **Step 1: Tighten existing tests to expect the new messages**

Update these assertions:

```csharp
stderr.Should().Contain(AuthMessages.LoginRequired);
```

for direct `NotAuthenticatedException` cases, and:

```csharp
stderr.Should().Contain(AuthMessages.AuthenticationFailed);
```

for `ApiException(401, ...)` cases.

Add `using AHKFlowApp.CLI.Services;` to any modified test file that does not already have it.

Update test throws that still construct the old message:

```csharp
.Throws(new NotAuthenticatedException(AuthMessages.LoginRequired));
```

- [ ] **Step 2: Run selected tests to verify they fail**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~AhkDownloadCommandTests|FullyQualifiedName~ZipDownloadCommandTests|FullyQualifiedName~NewHotstringCommandTests|FullyQualifiedName~ListHotstringCommandTests" --verbosity normal
```

Expected: fail on stale production messages.

- [ ] **Step 3: Update production messages**

In `DownloadCommandRunner.cs`, replace the 401 catch body message with:

```csharp
await stderr.WriteLineAsync(AuthMessages.AuthenticationFailed);
```

In `NewHotstringCommand.cs` and `ListHotstringCommand.cs`, replace each 401 catch body message with:

```csharp
await stderr.WriteLineAsync(AuthMessages.AuthenticationFailed);
```

Update `tests/AHKFlowApp.CLI.Tests/Infrastructure/StubAuthTokenProvider.cs`:

```csharp
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;

namespace AHKFlowApp.CLI.Tests.Infrastructure;

internal sealed class StubAuthTokenProvider(string? token) : IAuthTokenProvider
{
    public Task<string> GetTokenAsync(CancellationToken ct) =>
        token is null
            ? throw new NotAuthenticatedException(AuthMessages.LoginRequired)
            : Task.FromResult(token);

    public Task<LoginResult> LoginAsync(CancellationToken ct) => throw new NotImplementedException();
    public Task LogoutAsync(CancellationToken ct) => throw new NotImplementedException();
}
```

- [ ] **Step 4: Run selected tests to verify they pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~AhkDownloadCommandTests|FullyQualifiedName~ZipDownloadCommandTests|FullyQualifiedName~NewHotstringCommandTests|FullyQualifiedName~ListHotstringCommandTests" --verbosity normal
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add src/Tools/AHKFlowApp.CLI/Commands/Downloads/DownloadCommandRunner.cs src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/NewHotstringCommand.cs src/Tools/AHKFlowApp.CLI/Commands/Hotstrings/ListHotstringCommand.cs tests/AHKFlowApp.CLI.Tests/Infrastructure/StubAuthTokenProvider.cs tests/AHKFlowApp.CLI.Tests/Commands/Downloads tests/AHKFlowApp.CLI.Tests/Commands/Hotstrings
git commit -m "fix(029): replace temporary token auth messages"
```

---

## Task 5: Implement MSAL Device-Code Token Provider

**Files:**
- Create: `src/Tools/AHKFlowApp.CLI/Services/IAuthCachePathProvider.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/LocalAppDataAuthCachePathProvider.cs`
- Create: `src/Tools/AHKFlowApp.CLI/Services/MsalDeviceCodeTokenProvider.cs`
- Modify: `src/Tools/AHKFlowApp.CLI/Program.cs`
- Delete: `src/Tools/AHKFlowApp.CLI/Services/EnvVarAuthTokenProvider.cs`
- Delete: `tests/AHKFlowApp.CLI.Tests/Services/EnvVarAuthTokenProviderTests.cs`
- Test: `tests/AHKFlowApp.CLI.Tests/Services/MsalDeviceCodeTokenProviderTests.cs`

- [ ] **Step 1: Write failing provider tests**

Create `tests/AHKFlowApp.CLI.Tests/Services/MsalDeviceCodeTokenProviderTests.cs`:

```csharp
using AHKFlowApp.CLI;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Microsoft.Extensions.Options;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class MsalDeviceCodeTokenProviderTests : IDisposable
{
    private readonly string _tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task GetTokenAsync_InvalidClientId_ThrowsAuthConfigurationException()
    {
        var sut = CreateProvider(new CliOptions
        {
            ClientId = "",
            TenantId = Guid.NewGuid().ToString(),
        });

        Func<Task> act = () => sut.GetTokenAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<AuthConfigurationException>())
            .WithMessage("ClientId is not configured.");
    }

    [Fact]
    public async Task LoginAsync_InvalidTenantId_ThrowsAuthConfigurationException()
    {
        var sut = CreateProvider(new CliOptions
        {
            ClientId = Guid.NewGuid().ToString(),
            TenantId = "00000000-0000-0000-0000-000000000000",
        });

        Func<Task> act = () => sut.LoginAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<AuthConfigurationException>())
            .WithMessage("TenantId is not configured.");
    }

    [Fact]
    public async Task GetTokenAsync_NoCachedAccount_ThrowsNotAuthenticated()
    {
        var sut = CreateProvider(new CliOptions
        {
            ClientId = Guid.NewGuid().ToString(),
            TenantId = Guid.NewGuid().ToString(),
        });

        Func<Task> act = () => sut.GetTokenAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<NotAuthenticatedException>())
            .WithMessage(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task LogoutAsync_NoCacheFile_DoesNotThrow()
    {
        var sut = CreateProvider(new CliOptions
        {
            ClientId = Guid.NewGuid().ToString(),
            TenantId = Guid.NewGuid().ToString(),
        });

        Func<Task> act = () => sut.LogoutAsync(CancellationToken.None);

        await act.Should().NotThrowAsync();
    }

    private MsalDeviceCodeTokenProvider CreateProvider(CliOptions options)
    {
        Directory.CreateDirectory(_tempDir);
        var cache = Substitute.For<IAuthCachePathProvider>();
        cache.GetCacheFilePath().Returns(Path.Combine(_tempDir, "msal-cache.bin3"));

        return new MsalDeviceCodeTokenProvider(
            Options.Create(options),
            Substitute.For<IDeviceCodePromptWriter>(),
            cache);
    }
}
```

- [ ] **Step 2: Run provider tests to verify they fail**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~MsalDeviceCodeTokenProviderTests" --verbosity normal
```

Expected: fail because `MsalDeviceCodeTokenProvider` and cache path provider types do not exist.

- [ ] **Step 3: Add cache path providers**

Create `src/Tools/AHKFlowApp.CLI/Services/IAuthCachePathProvider.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public interface IAuthCachePathProvider
{
    string GetCacheFilePath();
}
```

Create `src/Tools/AHKFlowApp.CLI/Services/LocalAppDataAuthCachePathProvider.cs`:

```csharp
namespace AHKFlowApp.CLI.Services;

public sealed class LocalAppDataAuthCachePathProvider : IAuthCachePathProvider
{
    private const string CacheFileName = "msal-cache.bin3";
    private const string CacheDirectoryName = "AHKFlowApp";

    public string GetCacheFilePath()
    {
        string root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(root))
        {
            root = Environment.CurrentDirectory;
        }

        string directory = Path.Combine(root, CacheDirectoryName);
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, CacheFileName);
    }
}
```

- [ ] **Step 4: Add the MSAL provider**

Create `src/Tools/AHKFlowApp.CLI/Services/MsalDeviceCodeTokenProvider.cs`:

```csharp
using AHKFlowApp.CLI;
using AHKFlowApp.CLI.Exceptions;
using Microsoft.Extensions.Options;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Extensions.Msal;

namespace AHKFlowApp.CLI.Services;

public sealed class MsalDeviceCodeTokenProvider(
    IOptions<CliOptions> options,
    IDeviceCodePromptWriter promptWriter,
    IAuthCachePathProvider cachePathProvider) : IAuthTokenProvider
{
    private IPublicClientApplication? _app;
    private string[]? _scopes;
    private string? _cacheFilePath;

    public async Task<string> GetTokenAsync(CancellationToken ct)
    {
        IPublicClientApplication app = await GetAppAsync(ct);
        IAccount? account = (await app.GetAccountsAsync()).FirstOrDefault();
        if (account is null)
        {
            throw new NotAuthenticatedException(AuthMessages.LoginRequired);
        }

        try
        {
            AuthenticationResult result = await app
                .AcquireTokenSilent(_scopes!, account)
                .ExecuteAsync(ct);
            return result.AccessToken;
        }
        catch (MsalUiRequiredException)
        {
            throw new NotAuthenticatedException(AuthMessages.LoginRequired);
        }
    }

    public async Task<LoginResult> LoginAsync(CancellationToken ct)
    {
        IPublicClientApplication app = await GetAppAsync(ct);
        IAccount? account = (await app.GetAccountsAsync()).FirstOrDefault();
        if (account is not null)
        {
            try
            {
                AuthenticationResult silent = await app
                    .AcquireTokenSilent(_scopes!, account)
                    .ExecuteAsync(ct);
                return new LoginResult(silent.Account.Username, true);
            }
            catch (MsalUiRequiredException)
            {
            }
        }

        AuthenticationResult interactive = await app
            .AcquireTokenWithDeviceCode(_scopes!, async code =>
            {
                await promptWriter.WriteAsync(
                    new DeviceCodePrompt(
                        code.VerificationUrl,
                        code.UserCode,
                        code.Message),
                    ct);
            })
            .ExecuteAsync(ct);

        return new LoginResult(interactive.Account.Username, false);
    }

    public async Task LogoutAsync(CancellationToken ct)
    {
        IPublicClientApplication app = await GetAppAsync(ct);
        foreach (IAccount account in await app.GetAccountsAsync())
        {
            await app.RemoveAsync(account);
        }

        TryDeleteCacheFile();
    }

    private async Task<IPublicClientApplication> GetAppAsync(CancellationToken ct)
    {
        if (_app is not null)
        {
            return _app;
        }

        CliOptions config = options.Value;
        Guid clientId = ParseRequiredGuid(config.ClientId, nameof(config.ClientId));
        Guid tenantId = ParseRequiredGuid(config.TenantId, nameof(config.TenantId));

        _scopes = [$"api://{clientId}/access_as_user"];
        _cacheFilePath = cachePathProvider.GetCacheFilePath();

        _app = PublicClientApplicationBuilder
            .Create(clientId.ToString())
            .WithAuthority(AzureCloudInstance.AzurePublic, tenantId)
            .WithRedirectUri("http://localhost")
            .Build();

        StorageCreationProperties storageProperties = new StorageCreationPropertiesBuilder(
                Path.GetFileName(_cacheFilePath),
                Path.GetDirectoryName(_cacheFilePath)!)
            .Build();

        MsalCacheHelper cacheHelper = await MsalCacheHelper
            .CreateAsync(storageProperties)
            .WaitAsync(ct);
        cacheHelper.RegisterCache(_app.UserTokenCache);

        return _app;
    }

    private static Guid ParseRequiredGuid(string value, string key)
    {
        if (!Guid.TryParse(value, out Guid parsed) || parsed == Guid.Empty)
        {
            throw new AuthConfigurationException($"{key} is not configured.");
        }

        return parsed;
    }

    private void TryDeleteCacheFile()
    {
        if (_cacheFilePath is null)
        {
            return;
        }

        try
        {
            File.Delete(_cacheFilePath);
        }
        catch (Exception ex) when (ex is FileNotFoundException or IOException or UnauthorizedAccessException)
        {
        }
    }
}
```

- [ ] **Step 5: Replace DI registrations**

Modify `src/Tools/AHKFlowApp.CLI/Program.cs`. Replace:

```csharp
builder.Services.AddSingleton<IAuthTokenProvider, EnvVarAuthTokenProvider>();
builder.Services.AddTransient<BearerTokenHandler>();
```

with:

```csharp
builder.Services.AddSingleton<IDeviceCodePromptWriter, ConsoleErrorDeviceCodePromptWriter>();
builder.Services.AddSingleton<IAuthCachePathProvider, LocalAppDataAuthCachePathProvider>();
builder.Services.AddSingleton<IAuthTokenProvider, MsalDeviceCodeTokenProvider>();
builder.Services.AddTransient<BearerTokenHandler>();
```

- [ ] **Step 6: Delete the temporary env-var provider and tests**

Delete:

```text
src/Tools/AHKFlowApp.CLI/Services/EnvVarAuthTokenProvider.cs
tests/AHKFlowApp.CLI.Tests/Services/EnvVarAuthTokenProviderTests.cs
```

The CLI no longer reads `AHKFLOW_TOKEN`; test code should use `StubAuthTokenProvider` for fake tokens.

- [ ] **Step 7: Run provider tests to verify they pass**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --filter "FullyQualifiedName~MsalDeviceCodeTokenProviderTests" --verbosity normal
```

Expected: pass without requiring a real tenant.

- [ ] **Step 8: Run build**

Run:

```powershell
dotnet build src/Tools/AHKFlowApp.CLI --configuration Release
```

Expected: build succeeds.

- [ ] **Step 9: Verify help still works with zero GUID config**

Run:

```powershell
dotnet run --project src/Tools/AHKFlowApp.CLI -- --help
```

Expected: help output succeeds and lists `login`, `logout`, `hotstring`, and `download`.

- [ ] **Step 10: Verify lazy config error for auth command**

Run:

```powershell
dotnet run --project src/Tools/AHKFlowApp.CLI -- login
```

Expected: exit code `1`; stderr contains `ClientId is not configured.` because `appsettings.json` has `Guid.Empty`.

- [ ] **Step 11: Commit**

```powershell
git add src/Tools/AHKFlowApp.CLI/Services/IAuthCachePathProvider.cs src/Tools/AHKFlowApp.CLI/Services/LocalAppDataAuthCachePathProvider.cs src/Tools/AHKFlowApp.CLI/Services/MsalDeviceCodeTokenProvider.cs src/Tools/AHKFlowApp.CLI/Program.cs tests/AHKFlowApp.CLI.Tests/Services/MsalDeviceCodeTokenProviderTests.cs src/Tools/AHKFlowApp.CLI/Services/EnvVarAuthTokenProvider.cs tests/AHKFlowApp.CLI.Tests/Services/EnvVarAuthTokenProviderTests.cs
git commit -m "feat(029): add MSAL device-code token provider"
```

---

## Task 6: Update Entra App Registration Script

**Files:**
- Modify: `scripts/setup-entra-app.ps1`

- [ ] **Step 1: Insert public-client redirect URI setup after SPA redirect verification**

In `scripts/setup-entra-app.ps1`, after:

```powershell
Write-Host "Redirect URIs set: $($redirectUris -join ', ')"
```

insert:

```powershell
# ---------------------------------------------------------------------------
# Enable public-client device-code flow for the CLI
# ---------------------------------------------------------------------------
$publicClientRedirectUri = 'http://localhost'
$publicClientUris = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'publicClient.redirectUris' -o json 2>$null)
if (-not $publicClientUris) {
    $publicClientUris = @()
}

if ($publicClientRedirectUri -notin $publicClientUris) {
    $mergedPublicClientUris = @($publicClientUris) + $publicClientRedirectUri
    $publicClientJson = @{ publicClient = @{ redirectUris = $mergedPublicClientUris } } |
        ConvertTo-Json -Depth 5 -Compress
    Invoke-GraphPatch -ObjectId $objectId -JsonBody $publicClientJson
    Wait-ForCondition -Description "public client redirect URI" -Condition {
        $configuredUris = ConvertFrom-JsonSafe (az ad app show --id $objectId --query 'publicClient.redirectUris' -o json 2>$null)
        return $publicClientRedirectUri -in $configuredUris
    }
    Write-Host "Added public client redirect URI: $publicClientRedirectUri"
} else {
    Write-Host "Public client redirect URI already exists: $publicClientRedirectUri"
}

$isFallbackPublicClient = az ad app show --id $objectId --query 'isFallbackPublicClient' -o tsv 2>$null
if ($isFallbackPublicClient -ne 'true') {
    # Microsoft identity platform requires "allow public client flows" for device-code flow.
    # This Graph property is broader than the CLI command surface; AHKFlowApp only implements device-code, not ROPC.
    $fallbackJson = @{ isFallbackPublicClient = $true } | ConvertTo-Json -Compress
    Invoke-GraphPatch -ObjectId $objectId -JsonBody $fallbackJson
    Wait-ForCondition -Description "fallback public client flag" -Condition {
        $value = az ad app show --id $objectId --query 'isFallbackPublicClient' -o tsv 2>$null
        return $value -eq 'true'
    }
    Write-Host "Enabled fallback public client flow"
} else {
    Write-Host "Fallback public client flow already enabled"
}
```

- [ ] **Step 2: Run PowerShell parse check**

Run:

```powershell
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/setup-entra-app.ps1'), [ref]$null, [ref]$null)
```

Expected: no output and no exception.

- [ ] **Step 3: Commit**

```powershell
git add scripts/setup-entra-app.ps1
git commit -m "chore(029): enable CLI public-client auth in Entra setup"
```

---

## Task 7: Update Docs and Backlog

**Files:**
- Modify: `docs/architecture/authentication.md`
- Modify: `.claude/backlog/029-cli-authentication.md`

- [ ] **Step 1: Update authentication docs**

Replace the `## CLI authentication` section in `docs/architecture/authentication.md` with:

```markdown
## CLI authentication

The `ahkflow` CLI uses MSAL.NET device-code flow against the same per-environment Entra app registration as the Blazor frontend.

- **Commands**: `ahkflow login`, `ahkflow logout`
- **Scope**: `api://{clientId}/access_as_user`
- **Client type**: public client with redirect URI `http://localhost`
- **Token cache**: MSAL persisted user cache at `LocalApplicationData/AHKFlowApp/msal-cache.bin3`

`ahkflow login` tries silent token acquisition first. If the cache is empty or the refresh token requires interaction, the CLI prints the device-code URL and user code to stderr. API commands use `BearerTokenHandler`, which calls `IAuthTokenProvider.GetTokenAsync()` and attaches the cached access token.

Run `scripts/setup-entra-app.ps1 -Environment dev`, `scripts/setup-entra-app.ps1 -Environment test`, or `scripts/setup-entra-app.ps1 -Environment prod` to ensure the app registration has `publicClient.redirectUris` containing `http://localhost` and `isFallbackPublicClient=true`.
```

- [ ] **Step 2: Update backlog 029**

In `.claude/backlog/029-cli-authentication.md`, change the four acceptance criteria to checked:

```markdown
- [x] `ahkflow login` triggers device-code flow and caches the token.
- [x] Cached token is attached to all subsequent API calls.
- [x] `ahkflow logout` clears the cached token.
- [x] Expired tokens are refreshed silently; user is prompted to re-login on failure.
```

Append before `## Out of scope`:

```markdown
## Completion

**Completed:** 2026-05-10
```

- [ ] **Step 3: Commit**

```powershell
git add docs/architecture/authentication.md .claude/backlog/029-cli-authentication.md
git commit -m "docs(029): document CLI authentication"
```

---

## Task 8: Full Verification

**Files:**
- No new files. Verifies all previous tasks.

- [ ] **Step 1: Format check**

Run:

```powershell
dotnet format --verify-no-changes
```

Expected: succeeds with no changes. If formatting changes are needed, run `dotnet format`, inspect the diff, and commit:

```powershell
git add .
git commit -m "style(029): apply dotnet format"
```

- [ ] **Step 2: Build all projects**

Run:

```powershell
dotnet build --configuration Release --no-restore
```

Expected: succeeds.

- [ ] **Step 3: Run CLI tests**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --no-build --verbosity normal
```

Expected: succeeds.

- [ ] **Step 4: Run all tests**

Run:

```powershell
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: succeeds.

- [ ] **Step 5: Manual auth smoke**

Run after setting real dev values:

```powershell
$entra = .\scripts\setup-entra-app.ps1 -Environment dev | Where-Object {
    $_.PSObject.Properties['ClientId'] -and $_.ClientId
} | Select-Object -Last 1
$env:AHKFLOW_ApiBaseUrl = 'http://localhost:5600'
$env:AHKFLOW_ClientId = $entra.ClientId
$env:AHKFLOW_TenantId = $entra.TenantId
dotnet run --project src/Tools/AHKFlowApp.CLI -- login
dotnet run --project src/Tools/AHKFlowApp.CLI -- hotstring list
dotnet run --project src/Tools/AHKFlowApp.CLI -- logout
dotnet run --project src/Tools/AHKFlowApp.CLI -- hotstring list
```

Expected:

- `login` shows device-code instructions and then prints `Signed in as ...`.
- Authenticated `hotstring list` reaches the API.
- `logout` prints `Signed out`.
- Final `hotstring list` exits `3` with `Run 'ahkflow login' first.`.

- [ ] **Step 6: Final status check**

Run:

```powershell
git status --short --branch
```

Expected: clean branch `feature/029-cli-authentication`.

---

## Self-Review Checklist

- Spec requirement "login device-code flow and token cache" maps to Tasks 1, 3, 5, and 8.
- Spec requirement "cached token attached to API calls" maps to Task 5 through `IAuthTokenProvider` registration and existing `BearerTokenHandler`, with Task 8 tests.
- Spec requirement "logout clears cached token" maps to Tasks 3 and 5.
- Spec requirement "silent refresh or re-login prompt" maps to Task 5 `GetTokenAsync` and Task 8 smoke.
- Spec requirement "Entra setup public client" maps to Task 6.
- Spec requirement "stale auth messages" maps to Task 4.
- Spec requirement "docs/backlog" maps to Task 7.
