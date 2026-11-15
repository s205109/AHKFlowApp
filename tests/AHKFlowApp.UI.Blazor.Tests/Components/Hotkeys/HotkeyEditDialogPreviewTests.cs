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

public sealed class HotkeyEditDialogPreviewTests : HotkeyEditDialogTestsBase
{
    [Fact]
    public async Task PreviewPanel_CollapsedByDefault_DoesNotCallPreview()
    {
        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "K", ActionKind = HotkeyActionKind.SendText, Text = "hi" });

        await SetKeyAsync(provider, "key-picker", "L");

        _ = _api.DidNotReceive().PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task PreviewPanel_WhenExpanded_ShowsTheGeneratedSnippet()
    {
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("^k::Send \"hi\"")));

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "k", Ctrl = true, Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"preview-snippet\"]").TextContent.Should().Contain("^k::Send \"hi\""));
    }

    [Fact]
    public async Task PreviewPanel_DescriptionEdit_RepreviewsWithTheNewDescription()
    {
        // The generated snippet includes the Description as comment lines, so editing it must
        // re-preview like every other field feeding the snippet — not just clear its save error.
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet")));

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "k", Text = "hi", Description = "one" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.Description == "one"), Arg.Any<CancellationToken>()));

        provider.Find("input[data-test=\"description-input\"]").Input("two");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.Description == "two"), Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task PreviewPanel_KindChangeWhileExpanded_RepreviewsWithTheNewKind()
    {
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet")));

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "k", Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.ActionKind == HotkeyActionKind.SendText),
            Arg.Any<CancellationToken>()));

        await provider.Find("[data-test=\"action-kind-Disable\"]").ClickAsync(new MouseEventArgs());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.ActionKind == HotkeyActionKind.Disable),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task PreviewPanel_ValidationFailure_LandsOnItsNamedField()
    {
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]>
                    {
                        ["Input.Body"] = ["Braces must balance."],
                    })));

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "k", ActionKind = HotkeyActionKind.Raw, Body = "Send \"{" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("[data-test=\"preview-error\"]").Should().BeEmpty();
            provider.Markup.Should().Contain("Braces must balance.");
            // The panel body would otherwise be blank, which reads as broken rather than blocked.
            provider.Find("[data-test=\"preview-blocked\"]").TextContent
                .Should().Contain("Fix the highlighted fields");
        });
    }

    [Fact]
    public async Task PreviewPanel_ValidationKeyInADifferentCase_StillLandsOnItsField()
    {
        // The server may spell the property path in a case the model does not use. A
        // case-sensitive lookup would push this into the generic alert instead of onto the input.
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]>
                    {
                        ["input.body"] = ["Braces must balance."],
                    })));

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "k", ActionKind = HotkeyActionKind.Raw, Body = "Send \"{" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("[data-test=\"preview-error\"]").Should().BeEmpty(
                "the message belongs on the Body input, not in the panel");
            provider.Find("[data-test=\"preview-blocked\"]").TextContent
                .Should().Contain("Fix the highlighted fields");
        });
    }

    [Fact]
    public async Task PreviewPanel_OutOfOrderResponses_LaterGenerationWins()
    {
        TaskCompletionSource<ApiResult<HotkeyPreviewDto>> first = new();
        TaskCompletionSource<ApiResult<HotkeyPreviewDto>> second = new();
        _api.PreviewAsync(Arg.Is<HotkeyPreviewRequestDto>(r => r.Key == "one"), Arg.Any<CancellationToken>())
            .Returns(first.Task);
        _api.PreviewAsync(Arg.Is<HotkeyPreviewRequestDto>(r => r.Key == "two"), Arg.Any<CancellationToken>())
            .Returns(second.Task);

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "one", Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.Key == "one"), Arg.Any<CancellationToken>()));

        // Capture generation 1's run before generation 2 replaces the handle.
        Task staleRun = PreviewRun(provider);

        await SetKeyAsync(provider, "key-picker", "two");
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.Key == "two"), Arg.Any<CancellationToken>()));

        // Resolve the newer (generation 2) response first, then the superseded one. Cancellation
        // alone would not discard the stale response — only the generation check does.
        second.SetResult(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet-two")));
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("snippet-two"));

        first.SetResult(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet-one")));
        await staleRun;
        provider.Render();

        provider.Markup.Should().Contain("snippet-two");
        provider.Markup.Should().NotContain("snippet-one");
    }

    [Fact]
    public async Task PreviewPanel_UnexpectedFault_ClearsPendingAndShowsFriendlyError()
    {
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns<ApiResult<HotkeyPreviewDto>>(_ => throw new InvalidOperationException("boom"));

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogAsync(new HotkeyEditModel { Key = "k", Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("[data-test=\"preview-pending\"]").Should().BeEmpty(
                "an unexpected fault must not leave the spinner stuck forever");
            provider.Find("[data-test=\"preview-error\"]").TextContent.Should().NotBeNullOrWhiteSpace();
        });
    }

    [Fact]
    public async Task EachEvaluation_ReadsTheCatalogOnce()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Caps Lock as Ctrl",
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-destination").Should().Be("Ctrl"));

        _ = _knownShortcuts.Received(1).GetAsync(Arg.Any<CancellationToken>());

        await SetKeyAsync(provider, "remap-dest-picker", "LWin");

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-destination").Should().Be("LWin"));

        _ = _knownShortcuts.Received(2).GetAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task CatalogLoadFailure_StillWarnsAboutAModifierDestination()
    {
        // The modifier rule reads only the destination key, so it needs no catalog at all. An
        // outage must not take it away. The source side still says nothing, because deciding that
        // does need the list.
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(null));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Caps Lock as Ctrl",
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"destination-warning\"]").TextContent.Trim().Should().Be(
                "This hotkey makes CapsLock act as Ctrl. " +
                "Shortcuts that use Ctrl may also respond when you hold CapsLock."));

        provider.FindAll("[data-test=\"source-warning\"]").Should().BeEmpty();
        provider.FindAll(".mud-alert-filled-error").Should().BeEmpty();
    }

    [Fact]
    public async Task CatalogLoadFailure_AndNoSourceKeyYet_StillSaysNothing()
    {
        // The blank-key guard outranks the modifier rule: with no key there is nothing to name.
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(null));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Description = "Not finished yet",
            Key = "",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-destination").Should().Be("Ctrl"));

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task CatalogLoadFailure_ShowsNoWarningAndNoError()
    {
        // The catalog service turns a failed fetch into null, so that is what the dialog sees.
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(null));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "e", Win = true });

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();
        provider.FindAll(".mud-alert-filled-error").Should().BeEmpty();
    }

    [Fact]
    public async Task SlowResponseForAnOldCombination_CannotOverwriteTheNewerVerdict()
    {
        // Regression test for the generation counter. The first fetch is held open while the user
        // changes the key, so its response lands last and carries the old canonical key. The stub
        // ignores the cancellation token on purpose: that models a response already past the point
        // where cancelling helps, which leaves the generation check as the only thing guarding the
        // notice. Drop that check and the stale "Win+E opens File Explorer" line appears here.
        TaskCompletionSource<KnownShortcutCatalogDto?> gate = new();
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>()).Returns(
            _ => new ValueTask<KnownShortcutCatalogDto?>(gate.Task),
            _ => ValueTask.FromResult<KnownShortcutCatalogDto?>(WinECatalog()));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "e", Win = true });

        // The first evaluation is still waiting on the gate, so nothing is shown yet.
        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();

        // A newer combination. Its own fetch answers at once and matches nothing.
        await SetKeyAsync(provider, "key-picker", "F1");
        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();

        // Release the old fetch from inside the renderer, then flush: the continuation is queued
        // on the same dispatcher, so the second InvokeAsync runs after it.
        await provider.InvokeAsync(() => gate.SetResult(WinECatalog()));
        await provider.InvokeAsync(() => { });

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task ContextSwitch_TurnedOn_ShowsMatchTypeAndValueFields()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.FindAll("[data-test=\"context-match-type-select\"]").Should().BeEmpty();
        provider.FindAll("[data-test=\"context-value-input\"]").Should().BeEmpty();

        provider.Find("input[data-test=\"context-switch\"]").Change(true);

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"context-match-type-select\"]").Should().NotBeNull();
            provider.Find("[data-test=\"context-value-input\"]").Should().NotBeNull();
        });
    }

    [Fact]
    public async Task ContextSwitch_TurnedOff_ClearsBothContextFields()
    {
        HotkeyEditModel item = new() { Description = "d", Key = "K", Text = "hi" };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe");
        provider.WaitForAssertion(() => item.ContextValue.Should().Be("notepad.exe"));

        provider.Find("input[data-test=\"context-switch\"]").Change(false);

        provider.WaitForAssertion(() =>
        {
            item.ContextMatchType.Should().BeNull();
            item.ContextValue.Should().BeNull();
            provider.FindAll("[data-test=\"context-value-input\"]").Should().BeEmpty();
        });
    }

    [Fact]
    public async Task ContextValueField_ExecutableSelected_ShowsExePlaceholder()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);

        provider.WaitForAssertion(() =>
            provider.Find("input[data-test=\"context-value-input\"]")
                .GetAttribute("placeholder").Should().Be("notepad.exe"));
    }

    [Fact]
    public async Task PreviewPanel_ContextValueTyped_RepreviewsWithTheContext()
    {
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet")));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "k", Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.ContextMatchType == null), Arg.Any<CancellationToken>()));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r =>
                r.ContextMatchType == WindowMatchType.Executable && r.ContextValue == "notepad.exe"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task PreviewPanel_ContextSwitchOnWithBlankValue_SendsNullContext()
    {
        // Turning the switch on sets the match type but leaves the value blank. The server rejects
        // that pair, so the request must carry no context until the value is filled in.
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet")));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "k", Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);

        provider.WaitForAssertion(() => _api.Received(2).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.ContextMatchType == null && r.ContextValue == null),
            Arg.Any<CancellationToken>()));
    }

    [Theory]
    [InlineData("switch")]
    [InlineData("match-type")]
    [InlineData("value")]
    public async Task ChangingContext_ClearsAStaleCombinationConflict(string field)
    {
        // Window context is part of the uniqueness key, so a 409 from the last save no longer
        // applies once any context field changes.
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        HotkeyEditModel item = new()
        {
            Description = "Open palette",
            Key = "K",
            Text = "hi",
            ContextMatchType = WindowMatchType.Executable,
            ContextValue = "notepad.exe",
        };
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.Find("button.commit-edit").Click();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Hotkey already exists"));

        switch (field)
        {
            case "switch":
                provider.Find("input[data-test=\"context-switch\"]").Change(false);
                break;
            case "match-type":
                await provider.InvokeAsync(() => provider
                    .FindComponents<MudSelect<WindowMatchType>>()
                    .Single()
                    .Instance.ValueChanged.InvokeAsync(WindowMatchType.WindowClass));
                break;
            default:
                provider.Find("input[data-test=\"context-value-input\"]").Input("code.exe");
                break;
        }

        provider.WaitForAssertion(() => provider.Markup.Should().NotContain("Hotkey already exists"));
    }

    [Fact]
    public async Task TemplateNotice_AppearsWhenAProfileHeaderUsesTheRowsKey()
    {
        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [work.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Be("The header template in Work also uses CapsLock. Your hotkey may not fire."));
    }

    [Fact]
    public async Task TemplateNotice_AppearsWhenTheRowCarriesModifiers()
    {
        // A wildcard template hotkey fires whatever extra modifiers are held, so a row carrying
        // modifiers is affected just as much as a bare one. The notice names what the row presses.
        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            Ctrl = true,
            Shift = true,
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [work.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Be(
                    "The header template in Work also uses Ctrl+Shift+CapsLock. Your hotkey may not fire."));
    }

    [Fact]
    public async Task TemplateNotice_SkipsAPlainTemplateHotkeyWhenTheRowCarriesModifiers()
    {
        // "CapsLock::" with no wildcard fires only when nothing else is held, so this row is
        // untouched by it. The parser reads the modifiers, so the notice stays away.
        ProfileDto work = Profile("Work", "#Requires AutoHotkey v2.0\n\nCapsLock::Send \"hello\"");
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            Ctrl = true,
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [work.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]").GetAttribute("data-combination")
                .Should().Be("Ctrl+CapsLock"));

        provider.FindAll("[data-test=\"template-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task TemplateNotice_AppearsWhenATemplateHotkeyCarriesTheSameModifiers()
    {
        // The emitter writes "^!c::" for a Ctrl+Alt+C row (HotkeyEmitter.cs:38), which is the same
        // hotkey name the template line already defines.
        ProfileDto work = Profile("Work", "#Requires AutoHotkey v2.0\n\n^!c::Run \"calc.exe\"");
        HotkeyEditModel item = new()
        {
            Key = "c",
            Ctrl = true,
            Alt = true,
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [work.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Be("The header template in Work also uses Ctrl+Alt+C. Your hotkey may not fire."));
    }

    [Fact]
    public async Task TemplateNotice_StaysAwayWhenNoProfileTemplateUsesTheKey()
    {
        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        HotkeyEditModel item = new()
        {
            Key = "F9",
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [work.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]").GetAttribute("data-combination")
                .Should().Be("F9"));

        provider.FindAll("[data-test=\"template-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task TemplateNotice_IgnoresAProfileTheRowIsNotIn()
    {
        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        ProfileDto games = Profile("Games", "#Requires AutoHotkey v2.0");
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [games.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work, games);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]").GetAttribute("data-combination")
                .Should().Be("CapsLock"));

        provider.FindAll("[data-test=\"template-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task TemplateNotice_ReadsEveryProfileWhenTheRowAppliesToAll()
    {
        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = true,
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Contain("The header template in Work"));
    }

    [Fact]
    public async Task TemplateNotice_ReEvaluatesWhenProfileMembershipChangesWithoutTheKey()
    {
        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        ProfileDto games = Profile("Games", "#Requires AutoHotkey v2.0");
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.SendText,
            Text = "hi",
            AppliesToAllProfiles = false,
            ProfileIds = [games.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work, games);

        provider.WaitForAssertion(() =>
            provider.FindAll("[data-test=\"template-warning\"]").Should().BeEmpty());

        await provider.InvokeAsync(() => provider
            .FindComponents<EntityMultiSelect>()
            .Single(s => s.Instance.DataTest == "profile-select")
            .Instance.SelectedIdsChanged.InvokeAsync([work.Id]));

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"template-warning\"]").TextContent
                .Should().Contain("The header template in Work"));
    }

    [Fact]
    public async Task TemplateNotice_SitsBetweenTheSourceAndDestinationNotices()
    {
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(new KnownShortcutCatalogDto([
                new("windows.caps", "CapsLock", false, false, false, false,
                    [new("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "switch capitals on and off")],
                    null),
            ]));

        ProfileDto work = Profile("Work", CapsLockLayerHeader);
        HotkeyEditModel item = new()
        {
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "LCtrl",
            AppliesToAllProfiles = false,
            ProfileIds = [work.Id],
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogWithProfilesAsync(item, work);

        provider.WaitForAssertion(() =>
            provider.FindAll("[data-test=\"template-warning\"]").Should().NotBeEmpty());

        string[] order =
        [
            .. provider
                .FindAll("[data-test=\"source-warning\"], [data-test=\"template-warning\"], [data-test=\"destination-warning\"]")
                .Select(e => e.GetAttribute("data-test")!)
        ];

        order.Should().Equal("source-warning", "template-warning", "destination-warning");
    }
}
