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

public sealed class HotkeyEditDialogTests : BunitContext, IAsyncLifetime
{
    private static readonly HotkeyKeyDto[] CatalogKeys =
    [
        new("F1", "Function keys", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("c", "Letters & digits", ["HotkeyKey", "RemapDest", "SendToken"], false),
        new("Volume_Up", "Media & browser", ["SendToken"], true),
        new("Up", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("Down", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("Left", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("Right", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
    ];

    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    private readonly IHotkeyKeyCatalog _catalog = Substitute.For<IHotkeyKeyCatalog>();
    private readonly IKnownShortcutCatalog _knownShortcuts = Substitute.For<IKnownShortcutCatalog>();

    private static KnownShortcutCatalogDto WinECatalog() =>
        new([
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
        ]);

    // Win+E plus a bare F12 row. The F12 row is what a remap destination matches: a destination is
    // looked up with no modifiers at all.
    private static KnownShortcutCatalogDto WinEAndF12Catalog() =>
        new([
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
            new KnownShortcutDto("browser.devtools-f12", "F12", false, false, false, false,
                [new ShortcutUseDto("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open developer tools")],
                null),
        ]);

    public HotkeyEditDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());

        // Mirrors the real catalog: role filtering for the pickers, and the bracing rule the
        // SendKeys panel composes tokens with.
        _catalog.ForRoleAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult<IReadOnlyList<HotkeyKeyDto>>(
                [.. CatalogKeys.Where(k => k.Roles.Contains(call.Arg<string>()))]));
        _catalog.GroupOf(Arg.Any<string>())
            .Returns(call => CatalogKeys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.Group);
        _catalog.RequiresBracesInSend(Arg.Any<string>())
            .Returns(call => CatalogKeys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.RequiresBracesInSend ?? false);
        // Canonicalization is a real code path now: without this the substitute returns null and
        // every combination misses its catalog row.
        _catalog.CanonicalizeAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string>() ?? ""));
        Services.AddSingleton(_catalog);

        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(WinECatalog()));
        Services.AddSingleton(_knownShortcuts);

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    // Dialogs render only inside MudDialogProvider; every test needs the same three lines, so
    // they live here rather than being copied per test.
    private async Task<IRenderedComponent<MudDialogProvider>> ShowDialogAsync(HotkeyEditModel? item = null)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };
            if (item is not null)
                parameters[nameof(HotkeyEditDialog.Item)] = item;

            await dialogService.ShowAsync<HotkeyEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    // The key is a KeyPicker, not a plain text field: driving its ValueChanged is what a
    // selection from the dropdown does, without depending on popover/JS behaviour.
    private static bool IsChecked(IRenderedComponent<MudDialogProvider> provider, string dataTest) =>
        ((IHtmlInputElement)provider.Find($"input[data-test=\"{dataTest}\"]")).IsChecked;

    // Same idea for the modifier boxes: drive ValueChanged rather than the rendered input, so the
    // test does not depend on MudCheckBox's internal markup.
    private static Task SetModifierAsync(IRenderedComponent<MudDialogProvider> provider, string dataTest, bool value) =>
        provider.InvokeAsync(() => provider
            .FindComponents<MudCheckBox<bool>>()
            .Single(c => c.Instance.UserAttributes.TryGetValue("data-test", out object? v) && (string?)v == dataTest)
            .Instance.ValueChanged.InvokeAsync(value));

    private static Task SetKeyAsync(IRenderedComponent<MudDialogProvider> provider, string dataTest, string? key) =>
        provider.InvokeAsync(() => provider
            .FindComponents<KeyPicker>()
            .Single(p => p.Instance.DataTest == dataTest)
            .Instance.ValueChanged.InvokeAsync(key));

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
    public async Task CorrectingWindowOp_ClearsItsStaleSaveError()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Validation failed", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.WindowOp"] = ["Window requires an operation."] })));

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

        await SetKeyAsync(provider, "key-picker", "two");
        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotkeyPreviewRequestDto>(r => r.Key == "two"), Arg.Any<CancellationToken>()));

        // Resolve the newer (generation 2) response first, then the superseded one. Cancellation
        // alone would not discard the stale response — only the generation check does.
        second.SetResult(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet-two")));
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("snippet-two"));

        first.SetResult(ApiResult<HotkeyPreviewDto>.Ok(new HotkeyPreviewDto("snippet-one")));
        await Task.Delay(150);
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
    public async Task SaveError_OnContextValue_RendersInlineNotInTheGenericAlert()
    {
        const string message = "ContextValue must not contain double-quote characters.";
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

    private static ProfileDto Profile(string name, string header, string footer = "") =>
        new(Guid.NewGuid(), name, false, header, footer, DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);

    private const string CapsLockLayerHeader = """
        #Requires AutoHotkey v2.0

        *CapsLock::
        {
            SetKeyDelay -1
            Send "{Blind}{LCtrl DownR}"
        }
        """;

    private async Task<IRenderedComponent<MudDialogProvider>> ShowDialogWithProfilesAsync(
        HotkeyEditModel item,
        params ProfileDto[] profiles)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotkeyEditDialog.Item)] = item,
                [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)profiles,
                [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };

            await dialogService.ShowAsync<HotkeyEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
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
