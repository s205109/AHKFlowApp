using AHKFlowApp.UI.Blazor.Components.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class CliQuickstartCardTests : BunitContext, IAsyncLifetime
{
    public CliQuickstartCardTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_title_and_three_commands()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();

        cut.Markup.Should().Contain("CLI quickstart");
        cut.Markup.Should().Contain("ahkflow new");
        cut.Markup.Should().Contain("ahkflow list");
        cut.Markup.Should().Contain("ahkflow download");
    }

    [Fact]
    public void Copy_button_invokes_clipboard_writeText()
    {
        IRenderedComponent<CliQuickstartCard> cut = Render<CliQuickstartCard>();

        cut.FindAll("button.cli-copy-btn").First().Click();

        JSInterop.VerifyInvoke("navigator.clipboard.writeText");
    }
}
