using AHKFlowApp.UI.Blazor.Components.Home;
using AHKFlowApp.UI.Blazor.DTOs;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class RecentActivityCardTests : BunitContext, IAsyncLifetime
{
    public RecentActivityCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_each_item_with_label_and_action()
    {
        var now = DateTimeOffset.Parse("2026-05-13T12:00:00Z");
        RecentActivityItemDto[] items = new[]
        {
            new RecentActivityItemDto("hotstring", "created", "yw", now.AddMinutes(-2)),
            new RecentActivityItemDto("hotkey", "created", "Run Notepad", now.AddHours(-1)),
            new RecentActivityItemDto("profile", "updated", "Personal", now.AddDays(-1)),
        };

        IRenderedComponent<RecentActivityCard> cut = Render<RecentActivityCard>(ps => ps
            .Add(p => p.Items, items)
            .Add(p => p.UtcNow, now));

        cut.Markup.Should().Contain("Recent activity");
        cut.Markup.Should().Contain("yw");
        cut.Markup.Should().Contain("Run Notepad");
        cut.Markup.Should().Contain("Personal");
        cut.Markup.Should().Contain("2 min ago");
        cut.Markup.Should().Contain("1 h ago");
        cut.Markup.Should().Contain("Yesterday");
    }

    [Fact]
    public void Renders_empty_state_when_no_items()
    {
        IRenderedComponent<RecentActivityCard> cut = Render<RecentActivityCard>(ps => ps
            .Add(p => p.Items, Array.Empty<RecentActivityItemDto>())
            .Add(p => p.UtcNow, DateTimeOffset.UtcNow));

        cut.Markup.Should().Contain("No activity yet");
    }
}
