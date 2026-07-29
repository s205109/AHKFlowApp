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
            HotkeyActionKind.SendKeys, null, null, null, null, null, null, null,
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
                    HotkeyActionKind.SendKeys, null, null, null, null, null, null, null,
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
            HotkeyActionKind.SendKeys, null, "#{Left}", null, null, null, null, null,
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
            HotkeyActionKind.SendKeys, null, null, null, null, null, null, null,
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
}
