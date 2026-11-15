using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.Components.Hotkeys;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using AngleSharp.Html.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotkeys;

public sealed class HotkeyEditDialogActionTests : HotkeyEditDialogTestsBase
{
    [Fact]
    public async Task TogglingAModifier_ClearsAStaleCombinationConflict()
    {
        // A duplicate conflict is a verdict on the whole key+modifier combination. Toggling a
        // modifier changes that combination, so the stale conflict must clear off the key rather
        // than contradict a combination the server was never asked about.
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync();

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"description-input\"]"));
        provider.Find("input[data-test=\"description-input\"]").Input("Open palette");
        await SetKeyAsync(provider, "key-picker", "K");
        provider.Find("button.commit-edit").Click();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Hotkey already exists"));

        // The Ctrl modifier is the first bool checkbox on the panel.
        await provider.InvokeAsync(() =>
            provider.FindComponents<MudCheckBox<bool>>()[0].Instance.ValueChanged.InvokeAsync(true));

        provider.WaitForAssertion(() => provider.Markup.Should().NotContain("Hotkey already exists"));
    }

    [Fact]
    public async Task ActionSelector_OffersAllSevenKinds()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel());

        foreach (HotkeyActionKind kind in Enum.GetValues<HotkeyActionKind>())
            provider.FindAll($"[data-test=\"action-kind-{kind}\"]").Should().ContainSingle();
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, "sendtext-panel")]
    [InlineData(HotkeyActionKind.SendKeys, "sendkeys-panel")]
    [InlineData(HotkeyActionKind.Run, "run-panel")]
    [InlineData(HotkeyActionKind.Window, "window-panel")]
    [InlineData(HotkeyActionKind.Remap, "remap-panel")]
    [InlineData(HotkeyActionKind.Raw, "raw-panel")]
    public async Task SelectedKind_RevealsOnlyItsOwnPanel(HotkeyActionKind kind, string panelTest)
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { ActionKind = kind });

        provider.FindAll($"[data-test=\"{panelTest}\"]").Should().ContainSingle();
        provider.FindAll("[data-test$=\"-panel\"]").Should().ContainSingle();
    }

    [Fact]
    public async Task RunPanel_LabelsTheTargetPickerKindNotType()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { ActionKind = HotkeyActionKind.Run });

        // CONTEXT.md lists "type" under Avoid for Kind, Action, and Item. Lock the label
        // so it cannot drift back to "Target type".
        string panel = provider.Find("[data-test=\"run-panel\"]").InnerHtml;
        panel.Should().Contain("Target kind");
        panel.Should().NotContain("Target type");
    }

    [Fact]
    public async Task DisableKind_ShowsNoActionPanel()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { ActionKind = HotkeyActionKind.Disable });

        provider.FindAll("[data-test$=\"-panel\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task RawKind_ShowsTheUncheckedScriptWarning()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { ActionKind = HotkeyActionKind.Raw });

        provider.Find("[data-test=\"raw-warning\"]").TextContent
            .Should().Contain("stop the whole profile script from loading");
    }

    [Fact]
    public async Task SwitchingKind_KeepsTheOutgoingKindsTypedValue()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.Run, RunTarget = "notepad" };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        await provider.Find("[data-test=\"action-kind-SendText\"]").ClickAsync(new MouseEventArgs());

        item.ActionKind.Should().Be(HotkeyActionKind.SendText);
        item.RunTarget.Should().Be("notepad");   // retained, gated only on the wire
    }

    [Fact]
    public async Task SwitchingKind_SendsOnlyTheNewKindsFieldsOnSave()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.ServerError, null));
        HotkeyEditModel item = new()
        {
            Description = "Open palette",
            Key = "K",
            ActionKind = HotkeyActionKind.Run,
            RunTarget = "notepad",
        };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        await provider.Find("[data-test=\"action-kind-Disable\"]").ClickAsync(new MouseEventArgs());
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.ActionKind == HotkeyActionKind.Disable && d.RunTarget == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SwitchingKind_KeepsTheKeyConflictButDropsTheOutgoingKindsFieldError()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]>
                    {
                        ["Input.Key"] = ["Key is not a known key."],
                        ["Input.RunTarget"] = ["Run target is required."],
                    })));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "n", ActionKind = HotkeyActionKind.Run });

        provider.Find("button.commit-edit").Click();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Run target is required."));

        await provider.Find("[data-test=\"action-kind-Window\"]").ClickAsync(new MouseEventArgs());

        provider.Markup.Should().NotContain("Run target is required.");
        provider.Markup.Should().Contain("Key is not a known key.");
    }

    [Fact]
    public async Task CorrectingWindowOp_ClearsItsStaleSaveError()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.WindowOp"] = ["Choose an option in Do what."] })));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "n", ActionKind = HotkeyActionKind.Window });
        HotkeyEditDialog dialog = provider.FindComponent<HotkeyEditDialog>().Instance;

        provider.Find("button.commit-edit").Click();
        provider.WaitForAssertion(() =>
            dialog.SaveFieldErrors.Should().ContainKey(nameof(HotkeyEditModel.WindowOp)));

        await provider.InvokeAsync(() => provider.FindComponent<MudSelect<WindowOp?>>()
            .Instance.ValueChanged.InvokeAsync(WindowOp.Minimize));

        provider.WaitForAssertion(() =>
            dialog.SaveFieldErrors.Should().NotContainKey(nameof(HotkeyEditModel.WindowOp)));
    }

    // Expected ops are listed literally, not as Enum.GetValues<WindowOp>(): the dropdown builds its
    // items from that same call, so comparing against it could never fail. The literal catches the
    // dropdown narrowing its source — a hardcoded subset, or a .Where(...) filter over the enum.
    // Mirror completeness is a different failure, covered by WindowOpTests.MirrorsDomainEnum.
    // Asserting rendered items, rather than driving ValueChanged (which passes whether or not the
    // item exists), is what makes an unpickable op visible at all.
    [Fact]
    public async Task WindowPanel_OpDropdown_ListsEveryWindowOp()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { ActionKind = HotkeyActionKind.Window });

        IReadOnlyList<WindowOp?> items = [.. provider.FindComponents<MudSelectItem<WindowOp?>>()
            .Select(c => c.Instance.Value)];

        items.Should().BeEquivalentTo<WindowOp?>([
            WindowOp.Minimize, WindowOp.Maximize, WindowOp.Restore, WindowOp.Close,
            WindowOp.ToggleAlwaysOnTop, WindowOp.SnapLeft, WindowOp.SnapRight]);
    }

    [Fact]
    public async Task EmptyKey_BlocksSubmitClientSide()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Description = "Open palette" });

        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Key is required"));
        _ = _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task SendKeysPanel_ComposesModifiersAndBracedKeyIntoOneToken()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-ctrl-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", "Volume_Up");

        item.SendKeysContent.Should().Be("^{Volume_Up}");
    }

    [Fact]
    public async Task SendKeysPanel_SinglePrintableKeyIsNotBraced()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        await SetKeyAsync(provider, "send-key-picker", "c");

        item.SendKeysContent.Should().Be("c");
    }

    [Fact]
    public async Task SendKeysPanel_StoredTokenDecomposesIntoCheckboxesAndKey()
    {
        HotkeyEditModel item = new()
        {
            ActionKind = HotkeyActionKind.SendKeys,
            SendKeysContent = "^!{Volume_Up}",
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        IsChecked(provider, "send-ctrl-checkbox").Should().BeTrue();
        IsChecked(provider, "send-alt-checkbox").Should().BeTrue();
        IsChecked(provider, "send-shift-checkbox").Should().BeFalse();
        provider.Find("input[data-test=\"send-key-picker\"]").GetAttribute("value").Should().Be("Volume_Up");
    }

    // Injected Win is not honoured by the shell's Aero-Snap handler, so Send("#{Left}") silently
    // does nothing. All four arrows are the same gesture — Win+Up/Down maximize and minimize, and
    // fail the same way. Advisory only — see SendKeysPanel_WinArrowWarning_DoesNotBlockSave.
    [Theory]
    [InlineData("Up")]
    [InlineData("Down")]
    [InlineData("Left")]
    [InlineData("Right")]
    public async Task SendKeysPanel_WinPlusArrow_ShowsTheSnapWarning(string arrow)
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-win-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", arrow);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"send-win-arrow-warning\"]")
            .TextContent.Should().Contain("won't snap or resize the window"));
    }

    // Send "#e" really does open Explorer, so a blanket all-Win warning would be wrong: only the
    // arrow gesture is documented to fail.
    [Fact]
    public async Task SendKeysPanel_WinPlusNonArrow_ShowsNoWarning()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-win-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", "c");

        provider.FindAll("[data-test=\"send-win-arrow-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task SendKeysPanel_ArrowWithoutWin_ShowsNoWarning()
    {
        HotkeyEditModel item = new() { ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        await SetKeyAsync(provider, "send-key-picker", "Left");

        provider.FindAll("[data-test=\"send-win-arrow-warning\"]").Should().BeEmpty();
    }

    // Non-blocking by design: the token is valid AHK and the user may have a reason.
    [Fact]
    public async Task SendKeysPanel_WinArrowWarning_DoesNotBlockSave()
    {
        HotkeyDto created = new(Guid.NewGuid(), [], true, "Snap attempt", "n", true, false, false, false,
            HotkeyActionKind.SendKeys, null, "#{Left}", null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(created));

        HotkeyEditModel item = new() { Description = "Snap attempt", Key = "n", ActionKind = HotkeyActionKind.SendKeys };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("input[data-test=\"send-win-checkbox\"]").Change(true);
        await SetKeyAsync(provider, "send-key-picker", "Left");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.SendKeysContent == "#{Left}"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task ChangingModifier_IntoAKnownShortcut_ShowsWarning()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "e" });

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();

        await SetModifierAsync(provider, "win-checkbox", true);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning\"]").Should().NotBeNull());
    }

    [Fact]
    public async Task ChangingModifier_OutOfAKnownShortcut_ClearsWarning()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "e", Win = true });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning\"]").Should().NotBeNull());

        await SetModifierAsync(provider, "win-checkbox", false);

        provider.WaitForAssertion(() =>
            provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task ChangingOnlyTheRemapDestination_ReEvaluatesTheNotice()
    {
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(WinEAndF12Catalog()));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Caps Lock behaves as F12",
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "F12",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"destination-warning\"]").TextContent.Should().Contain("developer tools"));

        await SetKeyAsync(provider, "remap-dest-picker", "Ctrl");

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"destination-warning\"]").TextContent.Should().Contain(
                "Shortcuts that use Ctrl may also respond when you hold CapsLock."));
    }

    [Fact]
    public async Task SwitchingAwayFromRemap_ClearsTheDestinationNotice()
    {
        // The kind is part of what one evaluation is for. Drop it and this row keeps showing a
        // destination notice for an action that no longer has a destination.
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Caps Lock as Ctrl",
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"destination-warning\"]").TextContent
                .Should().Contain("Shortcuts that use Ctrl may also respond"));

        // The model keeps RemapDest across the switch on purpose, so only the kind changes here.
        await provider.Find("[data-test=\"action-kind-SendText\"]").ClickAsync(new MouseEventArgs());

        provider.WaitForAssertion(() =>
            provider.FindAll("[data-test=\"destination-warning\"]").Should().BeEmpty());
    }
}
