using System.CommandLine;
using AHKFlowApp.API;
using AHKFlowApp.CLI.Commands.Hotstrings;
using AHKFlowApp.CLI.Services;
using AHKFlowApp.CLI.Tests.Infrastructure;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Integration;

[Collection("CliWebApi")]
[Trait("Category", "Integration")]
public sealed class HotstringCliIntegrationTests(SqlContainerFixture sql) : IAsyncLifetime
{
    private WebApplicationFactory<Program> _factory = null!;
    private CustomWebApplicationFactory _baseFactory = null!;
    private readonly Guid _testUserOid = Guid.NewGuid();

    public Task InitializeAsync()
    {
        _baseFactory = new CustomWebApplicationFactory(sql);
        _factory = _baseFactory.WithTestAuth(u => u.WithOid(_testUserOid).WithEmail("test@example.com"));
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
        await _baseFactory.DisposeAsync();
    }

    private async Task<(int exit, string stdout, string stderr)> RunAsync(
        string[] args, string? token = "test-token", RequestCounter? counter = null)
    {
        IServiceProvider services = CliTestHost.WithFactory(_factory, token, counter);
        StringWriter so = new(), se = new();
        RootCommand root = new() { HotstringCommand.Build(services) };
        int exit = await root.Parse(args)
            .InvokeAsync(new InvocationConfiguration { Output = so, Error = se });
        return (exit, so.ToString(), se.ToString());
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

    private async Task<Hotstring> SeedHotstringAsync(string trigger, string replacement = "x", Guid? profileId = null)
    {
        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        HotstringBuilder b = new HotstringBuilder().WithOwner(_testUserOid).WithTrigger(trigger).WithReplacement(replacement);
        if (profileId is { } pid) b = b.InProfile(pid);
        Hotstring h = b.Build();
        db.Hotstrings.Add(h);
        await db.SaveChangesAsync();
        return h;
    }

    [Fact]
    public async Task Create_HappyPath_PersistsRow_Exit0()
    {
        (int exit, string? stdout, string _) = await RunAsync(["hotstring", "new", "-t", "btw", "-r", "by the way"]);

        exit.Should().Be(0);
        stdout.Should().StartWith("Created hotstring ");

        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Hotstring? row = await db.Hotstrings.FirstOrDefaultAsync(h => h.Trigger == "btw");
        row.Should().NotBeNull();
        row!.AppliesToAllProfiles.Should().BeTrue();
    }

    [Fact]
    public async Task List_HappyPath_RendersSeededTriggers()
    {
        await SeedHotstringAsync("aaa");
        await SeedHotstringAsync("bbb");

        (int exit, string? stdout, string _) = await RunAsync(["hotstring", "list"]);

        exit.Should().Be(0);
        stdout.Should().Contain("aaa");
        stdout.Should().Contain("bbb");
        stdout.Should().Contain("Kind");
    }

    [Fact]
    public async Task Create_WithProfile_CreatesJunctionRow()
    {
        Profile p = await SeedProfileAsync("work");

        (int exit, string _, string _) = await RunAsync(
            ["hotstring", "new", "-t", "wq", "-r", "work query", "-p", "work"]);

        exit.Should().Be(0);

        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Hotstring? row = await db.Hotstrings.Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Trigger == "wq");
        row.Should().NotBeNull();
        row!.AppliesToAllProfiles.Should().BeFalse();
        row.Profiles.Should().ContainSingle(j => j.ProfileId == p.Id);
    }

    [Fact]
    public async Task Create_NoProfile_AppliesToAll_NoJunctions()
    {
        (int exit, string _, string _) = await RunAsync(["hotstring", "new", "-t", "g1", "-r", "global"]);

        exit.Should().Be(0);

        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Hotstring? row = await db.Hotstrings.Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Trigger == "g1");
        row!.AppliesToAllProfiles.Should().BeTrue();
        row.Profiles.Should().BeEmpty();
    }

    [Fact]
    public async Task List_FilteredByProfile_IncludesScopedAndGlobal()
    {
        Profile p = await SeedProfileAsync("filt");
        await SeedHotstringAsync("scoped", profileId: p.Id);
        await SeedHotstringAsync("global");

        (int exit, string? stdout, string _) = await RunAsync(["hotstring", "list", "--profile", "filt"]);

        exit.Should().Be(0);
        stdout.Should().Contain("scoped");
        stdout.Should().Contain("global");
    }

    [Fact]
    public async Task Create_ProfileNameCaseInsensitive()
    {
        Profile p = await SeedProfileAsync("MixedCase");

        (int exit, string _, string _) = await RunAsync(
            ["hotstring", "new", "-t", "ci", "-r", "x", "-p", "mixedcase"]);

        exit.Should().Be(0);

        using IServiceScope scope = _factory.Services.CreateScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Hotstring? row = await db.Hotstrings.Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Trigger == "ci");
        row!.Profiles.Should().ContainSingle(j => j.ProfileId == p.Id);
    }

    [Fact]
    public async Task Create_DuplicateTrigger_Exit2()
    {
        await RunAsync(["hotstring", "new", "-t", "dup", "-r", "x"]);

        (int exit, string _, string? stderr) = await RunAsync(["hotstring", "new", "-t", "dup", "-r", "x"]);

        exit.Should().Be(2);
        stderr.Should().NotBeEmpty();
    }

    [Fact]
    public async Task Create_UnknownProfile_Exit2_ListsAvailable()
    {
        await SeedProfileAsync("known");

        (int exit, string _, string? stderr) = await RunAsync(
            ["hotstring", "new", "-t", "u1", "-r", "x", "-p", "missing"]);

        exit.Should().Be(2);
        stderr.Should().StartWith("Profile 'missing' not found. Available: ");
        stderr.Should().Contain("known");
    }

    [Fact]
    public async Task Create_ValidationFailure_Exit2()
    {
        (int exit, string _, string _) = await RunAsync(["hotstring", "new", "-t", " ", "-r", " "]);

        exit.Should().Be(2);
    }

    [Fact]
    public async Task List_Json_RoundtripsToPagedList()
    {
        await SeedHotstringAsync("json1");

        (int exit, string? stdout, string _) = await RunAsync(["hotstring", "list", "--json"]);

        exit.Should().Be(0);
        PagedList<HotstringDto>? parsed = System.Text.Json.JsonSerializer
            .Deserialize<PagedList<HotstringDto>>(stdout, System.Text.Json.JsonSerializerOptions.Web);
        parsed.Should().NotBeNull();
        parsed!.Items.Should().Contain(h => h.Trigger == "json1");
    }

    [Fact]
    public async Task List_JsonWithoutProfileFilter_DoesNotCallProfilesEndpoint()
    {
        await SeedHotstringAsync("opt1");
        RequestCounter counter = new();

        (int exit, string _, string _) = await RunAsync(["hotstring", "list", "--json"], counter: counter);

        exit.Should().Be(0);
        counter.ProfilesRequests.Should().Be(0);
    }

    [Fact]
    public async Task List_Pagination_ReturnsRequestedSlice()
    {
        for (int i = 0; i < 5; i++) await SeedHotstringAsync($"pg{i}");

        (int exit, string? stdout, string _) = await RunAsync(
            ["hotstring", "list", "--page", "2", "--page-size", "2", "--json"]);

        exit.Should().Be(0);
        PagedList<HotstringDto>? parsed = System.Text.Json.JsonSerializer
            .Deserialize<PagedList<HotstringDto>>(stdout, System.Text.Json.JsonSerializerOptions.Web);
        parsed!.Page.Should().Be(2);
        parsed.PageSize.Should().Be(2);
        parsed.Items.Count.Should().Be(2);
    }

    [Fact]
    public async Task List_Search_FiltersResults()
    {
        await SeedHotstringAsync("matchme");
        await SeedHotstringAsync("other");

        (int exit, string? stdout, string _) = await RunAsync(
            ["hotstring", "list", "--search", "matchme", "--json"]);

        exit.Should().Be(0);
        stdout.Should().Contain("matchme");
        stdout.Should().NotContain("other");
    }

    [Fact]
    public async Task Auth_TokenUnset_Exit3()
    {
        (int exit, string _, string? stderr) = await RunAsync(
            ["hotstring", "new", "-t", "x", "-r", "y"], token: null);

        exit.Should().Be(3);
        stderr.Should().Contain(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task Auth_MissingScope_Returns403_Exit1_ServerDetail()
    {
        await _factory.DisposeAsync();
        _factory = _baseFactory.WithTestAuth(u => u.WithOid(_testUserOid).WithoutScope());

        (int exit, string _, string? stderr) = await RunAsync(["hotstring", "new", "-t", "x", "-r", "y"]);

        exit.Should().Be(1);
        stderr.Should().NotBeEmpty();
        stderr.Should().NotContain(AuthMessages.LoginRequired);
    }
}
