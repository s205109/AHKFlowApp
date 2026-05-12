using System.CommandLine;
using AHKFlowApp.CLI.Commands.Hotstrings;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using AHKFlowApp.CLI.Tests.Infrastructure;
using FluentAssertions;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Commands.Hotstrings;

public sealed class NewHotstringCommandTests
{
    private static readonly Guid WorkId = Guid.NewGuid();
    private static readonly Guid HomeId = Guid.NewGuid();

    private static HotstringDto CreatedDto(string trigger = "btw") =>
        new(Guid.NewGuid(), [], true, trigger, "by the way", true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static (IHotstringsApiClient hs, IProfilesApiClient profiles) Fakes()
    {
        IHotstringsApiClient hs = Substitute.For<IHotstringsApiClient>();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>()).Returns(
            new List<ProfileSummary> { new(WorkId, "work"), new(HomeId, "home") });
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ci => CreatedDto(ci.Arg<CreateHotstringDto>().Trigger));
        return (hs, profiles);
    }

    private static async Task<(int exit, string stdout, string stderr)> Run(
        string[] args, IHotstringsApiClient hs, IProfilesApiClient profiles,
        IAuthTokenProvider? auth = null)
    {
        IServiceProvider services = CliTestHost.WithFakes(hs, profiles, auth: auth);
        StringWriter so = new(), se = new();
        RootCommand root = new() { HotstringCommand.Build(services) };
        int exit = await root.Parse(args)
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    [Fact]
    public async Task NoProfile_SendsAppliesToAllTrue_NullProfileIds()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string _, string _) = await Run(["hotstring", "new", "-t", "btw", "-r", "by the way"], hs, profiles);

        exit.Should().Be(0);
        await hs.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.ProfileIds == null && d.AppliesToAllProfiles),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task TwoProfiles_ResolvedAndAppliesToAllFalse()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string _, string _) = await Run(
            ["hotstring", "new", "-t", "btw", "-r", "by", "-p", "work", "-p", "home"], hs, profiles);

        exit.Should().Be(0);
        await hs.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d =>
                d.ProfileIds != null
                && d.ProfileIds.Length == 2
                && d.ProfileIds[0] == WorkId
                && d.ProfileIds[1] == HomeId
                && !d.AppliesToAllProfiles),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ProfileNameCaseInsensitive()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string _, string _) = await Run(
            ["hotstring", "new", "-t", "btw", "-r", "by", "-p", "WORK"], hs, profiles);

        exit.Should().Be(0);
        await hs.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.ProfileIds!.Length == 1 && d.ProfileIds[0] == WorkId),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task UnknownProfile_Exit2_StderrContainsAvailable()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string _, string? stderr) = await Run(
            ["hotstring", "new", "-t", "x", "-r", "y", "-p", "nope"], hs, profiles);

        exit.Should().Be(2);
        stderr.Should().StartWith("Profile 'nope' not found. Available: ");
        await hs.DidNotReceive().CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task DefaultsTrueForFlags()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        await hs.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.IsEndingCharacterRequired && d.IsTriggerInsideWord),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task NoEndingChar_FlipsFalse()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "new", "-t", "x", "-r", "y", "--no-ending-char"], hs, profiles);

        await hs.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => !d.IsEndingCharacterRequired && d.IsTriggerInsideWord),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task NoInsideWord_FlipsFalse()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "new", "-t", "x", "-r", "y", "--no-inside-word"], hs, profiles);

        await hs.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.IsEndingCharacterRequired && !d.IsTriggerInsideWord),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task JsonFlag_StdoutBeginsWithBrace()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string? stdout, string _) = await Run(
            ["hotstring", "new", "-t", "btw", "-r", "by the way", "--json"], hs, profiles);

        exit.Should().Be(0);
        stdout.TrimStart().Should().StartWith("{");
    }

    [Fact]
    public async Task NoJson_StdoutHumanSummary()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string? stdout, string _) = await Run(
            ["hotstring", "new", "-t", "btw", "-r", "by"], hs, profiles);

        exit.Should().Be(0);
        stdout.Should().StartWith("Created hotstring ");
    }

    [Theory]
    [InlineData(400)]
    [InlineData(409)]
    public async Task ApiException400Or409_Exit2(int status)
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new ApiException(status, "{\"title\":\"Conflict\"}"));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(2);
        stderr.Should().NotBeEmpty();
    }

    [Fact]
    public async Task ApiException401_Exit3_NotSignedIn()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new ApiException(401, null));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.AuthenticationFailed);
    }

    [Fact]
    public async Task ApiException403_Exit1_ServerDetail()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new ApiException(403, "Forbidden: missing scope"));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("Forbidden: missing scope");
    }

    [Fact]
    public async Task ApiException403_StoppedWebAppHtml_Exit1_FriendlyMessage()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new ApiException(
                403,
                "<!DOCTYPE html><html><head><title>Web App - Unavailable</title></head><body><h1>Error 403 - This web app is stopped.</h1></body></html>",
                "text/html"));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain(ApiMessages.WebAppUnavailable);
        stderr.Should().NotContain("<!DOCTYPE html>");
    }

    [Fact]
    public async Task ApiException500_Exit1()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new ApiException(500, "boom"));

        (int exit, string _, string _) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(1);
    }

    [Fact]
    public async Task HttpRequestException_Exit1()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new HttpRequestException("network down"));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("network down");
    }

    [Fact]
    public async Task NotAuthenticatedFromClient_Exit3()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new NotAuthenticatedException(AuthMessages.LoginRequired));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task AuthConfigurationException_Exit1()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Throws(new AuthConfigurationException("ClientId is not configured."));

        (int exit, string _, string? stderr) = await Run(["hotstring", "new", "-t", "x", "-r", "y"], hs, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("ClientId is not configured.");
    }
}
