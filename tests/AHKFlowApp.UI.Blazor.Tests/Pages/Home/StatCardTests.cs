using AHKFlowApp.UI.Blazor.Components.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class StatCardTests : BunitContext, IAsyncLifetime
{
    public StatCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_title_total_and_footer()
    {
        IRenderedComponent<StatCard> cut = Render<StatCard>(ps => ps
            .Add(p => p.Title, "HOTSTRINGS")
            .Add(p => p.Icon, Icons.Material.Outlined.Abc)
            .Add(p => p.Total, 15)
            .Add(p => p.FooterText, "+3 this week")
            .Add(p => p.DailyBuckets, new[] { 0, 1, 0, 2, 1, 0, 3, 1, 2, 0, 1, 1, 2, 1 }));

        cut.Markup.Should().Contain("HOTSTRINGS");
        cut.Markup.Should().Contain("15");
        cut.Markup.Should().Contain("+3 this week");
    }

    [Fact]
    public void Renders_with_empty_buckets()
    {
        IRenderedComponent<StatCard> cut = Render<StatCard>(ps => ps
            .Add(p => p.Title, "HOTKEYS")
            .Add(p => p.Icon, Icons.Material.Outlined.Keyboard)
            .Add(p => p.Total, 0)
            .Add(p => p.FooterText, "+0 this week")
            .Add(p => p.DailyBuckets, new int[14]));

        cut.Markup.Should().Contain("0");
        cut.Markup.Should().Contain("+0 this week");
    }
}
