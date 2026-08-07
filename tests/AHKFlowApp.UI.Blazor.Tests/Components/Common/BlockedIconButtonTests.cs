using AHKFlowApp.UI.Blazor.Components.Common;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Common;

public sealed class BlockedIconButtonTests : BunitContext, IAsyncLifetime
{
    private const string Reason = "Save your changes first";
    private const string ActionName = "Download the Work script";

    private readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();
    private IRenderedComponent<MudPopoverProvider>? _popovers;

    public BlockedIconButtonTests()
    {
        Services.AddMudServices();
        // Registered after AddMudServices so this substitute wins over MudBlazor's own snackbar.
        Services.AddSingleton(_snackbar);
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    // MudBlazor renders tooltip text into the popover provider's tree, not into the component.
    Task IAsyncLifetime.InitializeAsync()
    {
        _popovers = Render<MudPopoverProvider>();
        return Task.CompletedTask;
    }

    // MudBlazor's PopoverService is IAsyncDisposable-only; bUnit's sync Dispose throws on teardown.
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private IRenderedComponent<BlockedIconButton> RenderButton() =>
        Render<BlockedIconButton>(p => p
            .Add(c => c.Icon, Icons.Material.Filled.Download)
            .Add(c => c.Reason, Reason)
            .Add(c => c.AriaLabel, ActionName)
            .Add(c => c.Class, "download-profile-script"));

    [Fact]
    public void TheButton_IsNotDisabled_SoKeyboardAndTouchCanStillReachIt()
    {
        IRenderedComponent<BlockedIconButton> cut = RenderButton();

        IElement button = cut.Find("button");
        button.HasAttribute("disabled").Should().BeFalse();
        button.GetAttribute("aria-disabled").Should().Be("true");
    }

    [Fact]
    public void TheButton_KeepsTheClassThePageAsksFor()
    {
        IRenderedComponent<BlockedIconButton> cut = RenderButton();

        cut.Find("button").ClassList.Should().Contain("download-profile-script")
            .And.Contain("blocked-action");
    }

    [Fact]
    public void TheName_HoldsTheAction_AndTheDescriptionHoldsTheReason()
    {
        IRenderedComponent<BlockedIconButton> cut = RenderButton();

        IElement button = cut.Find("button");
        button.GetAttribute("aria-label").Should().Be(ActionName);

        string describedBy = button.GetAttribute("aria-describedby")!;
        IElement description = cut.Find($"#{describedBy}");
        description.TextContent.Should().Be(Reason);
        description.ClassList.Should().Contain("mud-sr-only");
    }

    // The touch path. A tap, a click, Enter, and Space all arrive here as one click event.
    [Fact]
    public void Activating_ShowsTheReason()
    {
        IRenderedComponent<BlockedIconButton> cut = RenderButton();

        cut.Find("button").Click();

        _snackbar.Received(1).Add(Reason, Severity.Info,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());
    }

    // The keyboard path. MudTooltip shows on focusin, and the button is focusable again.
    //
    // MudPopoverProvider renders one div per popover whether it is open or shut, and the div
    // always carries the tooltip's class. Only `mud-popover-open` tells the two apart, so the
    // test asserts the closed state first. Without that first assertion, a popover that was
    // already open would make this test pass for the wrong reason.
    [Fact]
    public void FocusingTheButton_ShowsTheReason()
    {
        IRenderedComponent<BlockedIconButton> cut = RenderButton();

        _popovers!.FindAll(".mud-popover-open.blocked-action-text").Should().BeEmpty();

        cut.Find("[data-test=\"blocked-action\"]").FocusIn(new FocusEventArgs());

        _popovers!.WaitForAssertion(() =>
            _popovers!.Find(".mud-popover-open.blocked-action-text").TextContent
                .Should().Contain(Reason));
    }

    [Fact]
    public void LosingFocus_HidesTheReason()
    {
        IRenderedComponent<BlockedIconButton> cut = RenderButton();
        IElement wrapper = cut.Find("[data-test=\"blocked-action\"]");

        wrapper.FocusIn(new FocusEventArgs());
        _popovers!.WaitForAssertion(() =>
            _popovers!.FindAll(".mud-popover-open.blocked-action-text").Should().ContainSingle());

        wrapper.FocusOut(new FocusEventArgs());

        _popovers!.WaitForAssertion(() =>
            _popovers!.FindAll(".mud-popover-open.blocked-action-text").Should().BeEmpty());
    }
}
