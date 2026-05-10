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
