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

public sealed class ListHotstringCommandTests
{
    private static readonly Guid WorkId = Guid.NewGuid();

    private static HotstringDto Hotstring(string trigger = "btw") =>
        new(Guid.NewGuid(), [], true, trigger, "by the way", true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static (IHotstringsApiClient hs, IProfilesApiClient profiles) Fakes(
        PagedList<HotstringDto>? page = null)
    {
        IHotstringsApiClient hs = Substitute.For<IHotstringsApiClient>();
        IProfilesApiClient profiles = Substitute.For<IProfilesApiClient>();
        profiles.ListAsync(Arg.Any<CancellationToken>()).Returns(
            new List<ProfileSummary> { new(WorkId, "work") });
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Returns(page ?? new PagedList<HotstringDto>([Hotstring()], 1, 50, 1));
        return (hs, profiles);
    }

    private static async Task<(int exit, string stdout, string stderr)> Run(
        string[] args, IHotstringsApiClient hs, IProfilesApiClient profiles)
    {
        IServiceProvider services = CliTestHost.WithFakes(hs, profiles);
        StringWriter so = new(), se = new();
        RootCommand root = new() { HotstringCommand.Build(services) };
        int exit = await root.Parse(args)
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
    }

    [Fact]
    public async Task PageAndPageSize_PassedThrough()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string _, string _) = await Run(["hotstring", "list", "--page", "2", "--page-size", "25"], hs, profiles);

        exit.Should().Be(0);
        await hs.Received(1).ListAsync(null, null, 2, 25, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ProfileFilter_ResolvedToGuid()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "list", "--profile", "work"], hs, profiles);

        await hs.Received(1).ListAsync(WorkId, null, 1, 50, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ProfileFilter_CaseInsensitive()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "list", "--profile", "WORK"], hs, profiles);

        await hs.Received(1).ListAsync(WorkId, null, 1, 50, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task SearchPassedThrough()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "list", "--search", "btw"], hs, profiles);

        await hs.Received(1).ListAsync(null, "btw", 1, 50, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task JsonFlag_StdoutBeginsWithBrace()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string? stdout, string _) = await Run(["hotstring", "list", "--json"], hs, profiles);

        exit.Should().Be(0);
        stdout.TrimStart().Should().StartWith("{");
    }

    [Fact]
    public async Task NoJson_RendersTableHeader()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string? stdout, string _) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(0);
        stdout.Should().Contain("Trigger");
        stdout.Should().Contain("Replacement");
    }

    [Fact]
    public async Task UnknownProfile_Exit2()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        (int exit, string _, string? stderr) = await Run(["hotstring", "list", "--profile", "nope"], hs, profiles);

        exit.Should().Be(2);
        stderr.Should().StartWith("Profile 'nope' not found. Available: ");
    }

    [Fact]
    public async Task ApiException400_Exit2()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Throws(new ApiException(400, "bad"));

        (int exit, string _, string _) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(2);
    }

    [Fact]
    public async Task ApiException401_Exit3()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Throws(new ApiException(401, null));

        (int exit, string _, string? stderr) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.AuthenticationFailed);
    }

    [Fact]
    public async Task ApiException403_Exit1_ServerDetail()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Throws(new ApiException(403, "Forbidden: missing scope"));

        (int exit, string _, string? stderr) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("Forbidden: missing scope");
    }

    [Fact]
    public async Task ApiException500_Exit1()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Throws(new ApiException(500, "boom"));

        (int exit, string _, string _) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(1);
    }

    [Fact]
    public async Task HttpRequestException_Exit1()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Throws(new HttpRequestException("network"));

        (int exit, string _, string _) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(1);
    }

    [Fact]
    public async Task EmptyPage_Exit0_StdoutPlaceholder()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes(new PagedList<HotstringDto>([], 1, 50, 0));

        (int exit, string? stdout, string _) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(0);
        stdout.Should().Contain("No hotstrings found.");
    }

    [Fact]
    public async Task JsonNoProfileFilter_DoesNotFetchProfiles()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "list", "--json"], hs, profiles);

        await profiles.DidNotReceive().ListAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task JsonWithProfileFilter_FetchesProfiles()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "list", "--json", "--profile", "work"], hs, profiles);

        await profiles.Received(1).ListAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task NoJsonNoProfileFilter_AllItemsApplyToAll_DoesNotFetchProfiles()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();

        await Run(["hotstring", "list"], hs, profiles);

        await profiles.DidNotReceive().ListAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task NoJsonNoProfileFilter_ScopedItemsPresent_FetchesProfilesForNameMap()
    {
        var pid = Guid.NewGuid();
        HotstringDto scoped = new(Guid.NewGuid(), [pid], false, "x", "y", true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes(
            new PagedList<HotstringDto>([scoped], 1, 50, 1));

        await Run(["hotstring", "list"], hs, profiles);

        await profiles.Received(1).ListAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task AuthConfigurationException_Exit1()
    {
        (IHotstringsApiClient? hs, IProfilesApiClient? profiles) = Fakes();
        hs.ListAsync(Arg.Any<Guid?>(), Arg.Any<string?>(), Arg.Any<int>(), Arg.Any<int>(),
                Arg.Any<CancellationToken>())
            .Throws(new AuthConfigurationException("TenantId is not configured."));

        (int exit, string _, string? stderr) = await Run(["hotstring", "list"], hs, profiles);

        exit.Should().Be(1);
        stderr.Should().Contain("TenantId is not configured.");
    }
}
