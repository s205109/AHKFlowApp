using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HomePageTests : BunitContext, IAsyncLifetime
{
    private readonly IDashboardApiClient _api = Substitute.For<IDashboardApiClient>();

    public HomePageTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static DashboardStatsDto SampleStats() => new(
        new EntityStatsDto(15, 3, new int[14]),
        new EntityStatsDto(6, 1, new int[14]),
        new ProfileStatsDto(5, 2, 1, new int[14]),
        [
            new RecentActivityItemDto("hotstring", "created", "yw", DateTimeOffset.UtcNow.AddMinutes(-2)),
        ]);

    [Fact]
    public void OnLoad_Renders_skeleton_until_data_arrives()
    {
        TaskCompletionSource<ApiResult<DashboardStatsDto>> tcs = new();
        _api.GetStatsAsync(Arg.Any<CancellationToken>()).Returns(tcs.Task);

        IRenderedComponent<AHKFlowApp.UI.Blazor.Pages.Home> cut = Render<AHKFlowApp.UI.Blazor.Pages.Home>();

        cut.Markup.Should().Contain("mud-skeleton");
    }

    [Fact]
    public void OnSuccess_Renders_all_four_sections()
    {
        _api.GetStatsAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<DashboardStatsDto>.Ok(SampleStats())));

        IRenderedComponent<AHKFlowApp.UI.Blazor.Pages.Home> cut = Render<AHKFlowApp.UI.Blazor.Pages.Home>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("Welcome to AHK");
        cut.Markup.Should().Contain("HOTSTRINGS");
        cut.Markup.Should().Contain("15");
        cut.Markup.Should().Contain("+3 this week");
        cut.Markup.Should().Contain("2 active");
        cut.Markup.Should().Contain("Recent activity");
        cut.Markup.Should().Contain("CLI quickstart");
    }

    [Fact]
    public void OnFailure_Renders_alert_plus_hero_and_cli()
    {
        _api.GetStatsAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<DashboardStatsDto>.Failure(ApiResultStatus.ServerError, null)));

        IRenderedComponent<AHKFlowApp.UI.Blazor.Pages.Home> cut = Render<AHKFlowApp.UI.Blazor.Pages.Home>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("mud-alert");
        cut.Markup.Should().Contain("Welcome to AHK");
        cut.Markup.Should().Contain("CLI quickstart");
    }
}
