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

public sealed class HotkeyEditDialogTests : HotkeyEditDialogTestsBase
{
    [Fact]
    public async Task CreateMode_RendersEmptyFields()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync();

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"key-picker\"]").GetAttribute("value").Should().Be(""));
        provider.Find("input[data-test=\"description-input\"]").GetAttribute("value").Should().Be("");
    }

    [Fact]
    public async Task EditMode_PrefillsFieldsFromItem()
    {
        HotkeyEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Description = "Open palette",
            Key = "K",
            Ctrl = true,
            Shift = true,
        };

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"key-picker\"]").GetAttribute("value").Should().Be("K"));
        provider.Find("input[data-test=\"description-input\"]").GetAttribute("value").Should().Be("Open palette");
    }

    [Fact]
    public async Task SaveInCreateMode_CallsCreateAsync()
    {
        HotkeyDto created = new(Guid.NewGuid(), [], true, "Open palette", "K", true, false, true, false,
            HotkeyActionKind.SendKeys, null, null, null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync();

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"description-input\"]"));
        provider.Find("input[data-test=\"description-input\"]").Input("Open palette");
        await SetKeyAsync(provider, "key-picker", "K");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.Description == "Open palette" && d.Key == "K"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveInEditMode_CallsUpdateAsync()
    {
        HotkeyEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Description = "Open palette",
            Key = "K",
            Ctrl = true,
        };
        _api.UpdateAsync(item.Id!.Value, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(
                new HotkeyDto(item.Id.Value, [], true, "Open palette", "P", true, false, false, false,
                    HotkeyActionKind.SendKeys, null, null, null, null, null, null, null, null, null,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"key-picker\"]"));
        await SetKeyAsync(provider, "key-picker", "P");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            item.Id.Value,
            Arg.Is<UpdateHotkeyDto>(d => d.Key == "P"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveConflict_ShowsKeyErrorInline()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync();

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"description-input\"]"));
        provider.Find("input[data-test=\"description-input\"]").Input("Open palette");
        await SetKeyAsync(provider, "key-picker", "K");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Hotkey already exists"));
        provider.FindAll(".mud-alert").Should().BeEmpty();
    }

    [Fact]
    public async Task ValidationError_FromSave_LandsOnItsNamedField()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]>
                    {
                        ["Input.RunTarget"] = ["Run target is required."],
                    })));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "n", ActionKind = HotkeyActionKind.Run });

        await provider.Find(".commit-edit").ClickAsync(new MouseEventArgs());

        provider.WaitForAssertion(() =>
        {
            provider.Markup.Should().Contain("Run target is required.");
            // Landing inline is the whole point: a message that only reached the generic
            // bottom-of-dialog alert would satisfy the Contain check above just as well.
            provider.FindAll(".mud-alert").Should().BeEmpty();
        });
    }

    [Fact]
    public async Task SaveError_SurvivesAnInFlightPreviewResponse()
    {
        // The preview call is left pending until after Save has failed, reproducing the race:
        // a response arriving late must not wipe the save verdict off the field.
        TaskCompletionSource<ApiResult<HotkeyPreviewDto>> preview = new();
        _api.PreviewAsync(Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(preview.Task);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "k", Text = "hi" });

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Any<HotkeyPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        provider.Find("button.commit-edit").Click();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Hotkey already exists"));

        preview.SetResult(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("k::Send \"hi\"")));

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("k::Send \"hi\""));
        provider.Markup.Should().Contain("Hotkey already exists");
    }

    [Fact]
    public async Task EditingAFieldWithASaveError_ClearsOnlyThatFieldsStaleError()
    {
        // The finding: a save error keyed to a field must drop from state the moment the user edits
        // that field, so it cannot outlive — and contradict — the value it judged. Because MudBlazor
        // inputs mask a field's stale explicit error once its own value changes, the observable seam
        // is _saveFieldErrors, not the rendered markup: the edited field's key must go while an
        // untouched field's key stays (proving only the edited field is cleared, per Task 8's
        // isolation contract).
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]>
                    {
                        ["Input.RunTarget"] = ["Run target is required."],
                        ["Input.Description"] = ["Description is not allowed."],
                    })));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "n", ActionKind = HotkeyActionKind.Run });
        HotkeyEditDialog dialog = provider.FindComponent<HotkeyEditDialog>().Instance;

        provider.Find("button.commit-edit").Click();
        provider.WaitForAssertion(() =>
            dialog.SaveFieldErrors.Keys.Should().BeEquivalentTo(
                [nameof(HotkeyEditModel.RunTarget), nameof(HotkeyEditModel.Description)]));

        // Edit the RunTarget: after its debounce fires, only its own stale save error is dropped.
        provider.Find("input[data-test=\"run-target-input\"]").Input("notepad.exe");

        provider.WaitForAssertion(() =>
        {
            dialog.SaveFieldErrors.Should().NotContainKey(nameof(HotkeyEditModel.RunTarget));
            // The untouched field keeps its verdict — the error isolation is preserved.
            dialog.SaveFieldErrors.Should().ContainKey(nameof(HotkeyEditModel.Description));
        });
    }

    [Fact]
    public async Task ValidationError_ForAnUnknownField_FallsBackToTheGenericAlert()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]>
                    {
                        ["Input.ProfileIds"] = ["Unknown profile."],
                    })));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "d", Key = "n", ActionKind = HotkeyActionKind.SendText });

        await provider.Find(".commit-edit").ClickAsync(new MouseEventArgs());

        provider.WaitForAssertion(() =>
            provider.Find(".mud-alert").TextContent.Should().Contain("Unknown profile."));
    }

    [Fact]
    public async Task Open_ExistingHotkeyMatchingAKnownShortcut_ShowsWarning()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Id = Guid.NewGuid(), Key = "e", Win = true, Description = "Open notes" });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning\"]").TextContent
                .Should().Contain("Windows uses Win+E to open File Explorer."));

        // One notice, so no section labels. They appear only when both sides warn, which is what
        // keeps a source-only notice reading exactly as it read before the destination check.
        provider.Find("[data-test=\"shortcut-warning\"]").TextContent
            .Should().NotContain("Key and modifiers").And.NotContain("Remap destination");
    }

    [Fact]
    public async Task Open_AfterDeciding_AnnouncesTheCombinationItDecidedFor()
    {
        // The E2E flows read this hook to tell "no warning" apart from "not decided yet".
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "F1", Ctrl = true });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-combination").Should().Be("Ctrl+F1"));
    }

    [Fact]
    public async Task Open_CombinationWithNoKnownShortcut_ShowsNoWarning()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "F1", Ctrl = true });

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Open_RemapToAModifier_WarnsAboutTheDestination()
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
            provider.Find("[data-test=\"destination-warning\"]").TextContent.Trim().Should().Be(
                "This hotkey makes CapsLock act as Ctrl. " +
                "Shortcuts that use Ctrl may also respond when you hold CapsLock."));

        // Destination-only notice: still no labels. CapsLock matches no catalog row, so the source
        // side says nothing.
        provider.FindAll("[data-test=\"source-warning\"]").Should().BeEmpty();
        provider.Find("[data-test=\"shortcut-warning\"]").TextContent
            .Should().NotContain("Key and modifiers").And.NotContain("Remap destination");
    }

    [Fact]
    public async Task Open_RemapToAKnownKey_MatchesItWithNoModifiers()
    {
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(WinEAndF12Catalog()));

        // The row carries Ctrl. The destination is still matched bare, because AHK releases a
        // modifier that is on the source and not on the destination.
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Ctrl+C behaves as F12",
            Key = "c",
            Ctrl = true,
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "F12",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"destination-warning\"]").TextContent.Trim().Should().Be(
                "This hotkey makes Ctrl+C act as F12. " +
                "Chrome uses F12 to open developer tools, but only while that application is in front."));
    }

    [Fact]
    public async Task Open_NotARemapButRemapDestRetained_SaysNothingAboutTheDestination()
    {
        // The edit model keeps per-kind fields across kind switches on purpose, so a SendText row
        // can still carry a destination from an earlier switch. It must stay silent.
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Types a note",
            Key = "CapsLock",
            ActionKind = HotkeyActionKind.SendText,
            Text = "my notes",
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-combination").Should().Be("CapsLock"));

        provider.FindAll("[data-test=\"destination-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Open_RemapWithNoSourceKeyYet_SaysNothingAboutTheDestination()
    {
        // A new row can reach Remap and a destination before its key is picked. Without a key the
        // notice would read "This hotkey makes  act as Ctrl." — a sentence with a hole in it.
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Description = "Not finished yet",
            Key = "",
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        // The destination is still announced, so this waits for a real decision rather than for
        // the evaluation that has not run yet.
        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-destination").Should().Be("Ctrl"));

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Open_RemapWithModifiersButNoSourceKey_SaysNothingAboutTheDestination()
    {
        // Modifiers alone make ComboLabel return "Ctrl+", which is not blank but still names no
        // key. The notice must wait for the key here too.
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Description = "Not finished yet",
            Key = "",
            Ctrl = true,
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning-checked\"]")
                .GetAttribute("data-destination").Should().Be("Ctrl"));

        provider.FindAll("[data-test=\"shortcut-warning\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Open_BothSidesWarn_ShowsLabelledSectionsInOneAlert()
    {
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Id = Guid.NewGuid(),
            Description = "Win+E behaves as Ctrl",
            Key = "e",
            Win = true,
            ActionKind = HotkeyActionKind.Remap,
            RemapDest = "Ctrl",
        });

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("[data-test=\"shortcut-warning\"]").Should().HaveCount(1);
            provider.Find("[data-test=\"source-warning\"]").TextContent
                .Should().Contain("Windows uses Win+E to open File Explorer.");
            provider.Find("[data-test=\"destination-warning\"]").TextContent
                .Should().Contain("Shortcuts that use Ctrl may also respond");
            provider.Find("[data-test=\"shortcut-warning\"]").TextContent
                .Should().Contain("Key and modifiers").And.Contain("Remap destination");
        });
    }

    [Fact]
    public async Task Save_IsNeverBlockedByAWarning()
    {
        HotkeyDto created = new(Guid.NewGuid(), [], true, "Open notes", "e", false, false, false, true,
            HotkeyActionKind.SendKeys, null, null, null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Key = "e", Win = true, Description = "Open notes" });

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"shortcut-warning\"]").Should().NotBeNull());

        provider.Find("button.commit-edit").HasAttribute("disabled").Should().BeFalse();
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Save_WithContext_SendsContextInCreateDto()
    {
        HotkeyDto created = new(Guid.NewGuid(), [], true, "Open palette", "K", false, false, false, false,
            HotkeyActionKind.SendText, "hi", null, null, null, null, null, null,
            WindowMatchType.Executable, "notepad.exe",
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(
            new HotkeyEditModel { Description = "Open palette", Key = "K", Text = "hi" });
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d =>
                d.ContextMatchType == WindowMatchType.Executable && d.ContextValue == "notepad.exe"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveError_OnContextValue_RendersInlineNotInTheGenericAlert()
    {
        const string message = "Value under Window context must not contain double quotes.";
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.ContextValue"] = [message] })));

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(new HotkeyEditModel
        {
            Description = "Open palette",
            Key = "K",
            Text = "hi",
            ContextMatchType = WindowMatchType.Executable,
            ContextValue = "note\"pad.exe",
        });
        HotkeyEditDialog dialog = provider.FindComponent<HotkeyEditDialog>().Instance;

        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() =>
        {
            dialog.SaveFieldErrors.Should().ContainKey(nameof(HotkeyEditModel.ContextValue));
            MudTextField<string> valueField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Value").Instance;
            valueField.GetState(x => x.Error).Should().BeTrue();
            valueField.GetState(x => x.ErrorText).Should().Be(message);
        });
        provider.FindAll(".mud-alert").Should().BeEmpty();
    }

    // Backlog 211: the hotkey dialog gave no reason for an empty Profiles field either.
    [Fact]
    public async Task EditMode_ItemWithNoProfile_ShowsTheNoticeUntilApplyToAllIsOn()
    {
        // Built the way the hotkey page opens the dialog: from the stored DTO, then cloned.
        HotkeyEditModel item = HotkeyEditModel.FromDto(new HotkeyDto(Guid.NewGuid(), [], false, "Open terminal", "T",
            true, false, false, false, HotkeyActionKind.Run, null, null, "wt.exe", RunTargetKind.Application,
            null, null, null, null, null, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)).Clone();

        IRenderedComponent<MudDialogProvider> provider =
            await ShowDialogWithProfilesAsync(item, Profile("Work", "#Requires AutoHotkey v2.0"));

        provider.WaitForAssertion(() => provider.Find("[data-test=\"no-profile-notice\"]").TextContent
            .Should().Contain("This item applies to no profile, so no script contains it. Choose its profiles, or turn on Apply to all profiles."));

        provider.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(true);

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"no-profile-notice\"]").Should().BeEmpty());
    }

    // Backlog 175: a rule on a field the dialog does not show, such as Body on a Send text hotkey,
    // had nowhere to appear. A rule on a visible select belongs on that select, not in the notice.
    // Turning on Apply to all profiles must not hide the notice.
    [Fact]
    public async Task EditMode_RuleOnAFieldNotShown_ListedInANoticeThatOutlastsApplyToAll()
    {
        const string body = "Action body is only valid for the Raw action.";
        const string matchBy = "Match by and Value under Window context must both be set, or both be empty.";
        HotkeyEditModel item = HotkeyEditModel.FromDto(new HotkeyDto(
            Guid.NewGuid(), [], false, "Greet", "F1", false, false, false, false,
            HotkeyActionKind.SendText, "hi", null, null, null, null, null, "Send x",
            WindowMatchType.TitleContains, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            BrokenRules: [new("Body", body), new("ContextMatchType", matchBy)])).Clone();
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"broken-rules-notice\"]").TextContent
            .Should().Contain("These rules belong to fields that are not shown:").And.Contain(body)
            .And.NotContain(matchBy));
        provider.WaitForAssertion(() =>
            provider.FindComponents<MudSelect<WindowMatchType>>().Single(s => s.Instance.Label == "Match by").Instance
                .GetState(x => x.ErrorText).Should().Be(matchBy));
        provider.FindAll("[data-test=\"no-profile-notice\"]").Should().ContainSingle();

        provider.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(true);

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"no-profile-notice\"]").Should().BeEmpty());
        provider.FindAll("[data-test=\"broken-rules-notice\"]").Should().ContainSingle();
    }

    // Backlog 175: MudBlazor validates some inputs once the dialog opens, and that clears an Error
    // set from outside. Every kind of input must still show its broken rule at open.
    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Key")]
    [InlineData(HotkeyActionKind.SendText, "Description")]
    [InlineData(HotkeyActionKind.SendText, "Text")]
    [InlineData(HotkeyActionKind.SendKeys, "SendKeysContent")]
    [InlineData(HotkeyActionKind.Run, "RunTarget")]
    [InlineData(HotkeyActionKind.Run, "RunTargetKind")]
    [InlineData(HotkeyActionKind.Window, "WindowOp")]
    [InlineData(HotkeyActionKind.Remap, "RemapDest")]
    [InlineData(HotkeyActionKind.Raw, "Body")]
    [InlineData(HotkeyActionKind.SendText, "ContextMatchType")]
    [InlineData(HotkeyActionKind.SendText, "ContextValue")]
    public async Task EditMode_BrokenRule_ShowsOnItsOwnInputAtOpen(HotkeyActionKind kind, string field)
    {
        string message = $"Broken {field}.";
        HotkeyEditModel item = HotkeyEditModel.FromDto(new HotkeyDto(
            Guid.NewGuid(), [], true, "Greet", "F1", false, false, false, false,
            kind, "t", "^a", "notepad.exe", Enum.GetValues<RunTargetKind>().First(), Enum.GetValues<WindowOp>().First(), "F2", "body",
            WindowMatchType.TitleContains, "x",
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            BrokenRules: [new(field, message)])).Clone();

        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);

        provider.WaitForAssertion(() => provider.Markup.Should().Contain(message));
        provider.Find("[data-test=\"broken-rules-notice\"]").TextContent.Should()
            .NotContain(message, "the input shows it, so the notice does not list it again");
    }

    // Backlog 175 (final review): MudBlazor validates a text field when it loses focus, and that
    // cleared an Error set from outside. An Owner who tabs through the form must still see the marks.
    [Theory]
    [InlineData(HotkeyActionKind.SendText, "key-picker", "Key")]
    [InlineData(HotkeyActionKind.SendText, "description-input", "Description")]
    [InlineData(HotkeyActionKind.SendText, "text-input", "Text")]
    [InlineData(HotkeyActionKind.SendKeys, "send-key-picker", "SendKeysContent")]
    [InlineData(HotkeyActionKind.Run, "run-target-input", "RunTarget")]
    [InlineData(HotkeyActionKind.Remap, "remap-dest-picker", "RemapDest")]
    [InlineData(HotkeyActionKind.Raw, "raw-body-input", "Body")]
    [InlineData(HotkeyActionKind.SendText, "context-value-input", "ContextValue")]
    public async Task EditMode_BrokenRule_StaysMarkedWhenTheFieldLosesFocusUnchanged(HotkeyActionKind kind, string dataTest, string field)
    {
        string message = $"Broken {field}.";
        HotkeyEditModel item = HotkeyEditModel.FromDto(new HotkeyDto(
            Guid.NewGuid(), [], true, "Greet", "F1", false, false, false, false,
            kind, "t", "^a", "notepad.exe", Enum.GetValues<RunTargetKind>().First(), Enum.GetValues<WindowOp>().First(), "F2", "body",
            WindowMatchType.TitleContains, "x",
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            BrokenRules: [new(field, message)])).Clone();
        IRenderedComponent<MudDialogProvider> provider = await ShowDialogAsync(item);
        provider.WaitForAssertion(() => provider.Markup.Should().Contain(message));

        await provider.InvokeAsync(() => provider
            .Find($"input[data-test=\"{dataTest}\"], textarea[data-test=\"{dataTest}\"], [data-test=\"{dataTest}\"] input")
            .Blur());

        provider.Markup.Should().Contain(message);
    }
}
