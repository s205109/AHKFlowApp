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
