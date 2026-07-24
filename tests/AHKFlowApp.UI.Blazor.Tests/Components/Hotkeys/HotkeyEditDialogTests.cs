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
    ];

    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    private readonly IHotkeyKeyCatalog _catalog = Substitute.For<IHotkeyKeyCatalog>();

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
        Services.AddSingleton(_catalog);

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
}
