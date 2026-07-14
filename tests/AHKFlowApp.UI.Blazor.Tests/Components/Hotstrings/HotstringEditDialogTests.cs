using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringEditDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();
    private readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();

    public HotstringEditDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(_snackbar);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public async Task CreateMode_RendersEmptyFields()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be(""));
        provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Be("");
    }

    [Fact]
    public async Task EditMode_PrefillsFieldsFromItem()
    {
        HotstringEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
            Description = "polite filler",
        };

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Item)] = item,
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be("btw"));
        provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Contain("by the way");
    }

    [Fact]
    public async Task SaveInCreateMode_CallsCreateAsync()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        provider.Find("input[data-test=\"trigger-input\"]").Input("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveInEditMode_CallsUpdateAsync()
    {
        HotstringEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
        };
        _api.UpdateAsync(item.Id!.Value, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(item.Id.Value, [], true, "btw", "by the way!", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Item)] = item,
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("textarea[data-test=\"replacement-input\"]"));
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            item.Id.Value,
            Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveConflict_ShowsTriggerErrorInline()
    {
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", null, null)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        provider.Find("input[data-test=\"trigger-input\"]").Input("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Trigger already exists"));
        provider.FindAll(".mud-alert").Should().BeEmpty();
    }

    [Fact]
    public async Task SaveInCreateMode_WithCaseSensitiveChecked_SendsNewFlags()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        provider.Find("input[data-test=\"trigger-input\"]").Input("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        provider.Find("input[data-test=\"case-sensitive-checkbox\"]").Change(true);
        provider.Find("input[data-test=\"omit-ending-checkbox\"]").Change(true);
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.IsCaseSensitive && d.OmitEndingCharacter),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task KindSelector_Renders()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]").Should().NotBeNull());
    }

    [Fact]
    public async Task SwitchToDateTime_WithEmptyReplacement_HidesReplacementAndShowsDateTimePanel()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("textarea[data-test=\"replacement-input\"]").Should().BeEmpty();
            provider.Find("[data-test=\"datetime-format-select\"]").Should().NotBeNull();
        });
    }

    [Fact]
    public async Task SelectingPreset_SetsFormatAndRoundTripsIntoSavedDto()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "date", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));

        await SelectFormatAsync(provider, "yyyy-MM-dd");

        provider.Find("input[data-test=\"trigger-input\"]").Input("date");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.DateTime
                && d.DateTimeFormat == "yyyy-MM-dd"
                && d.Replacement == ""),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SelectingCustom_RevealsCustomFormatField()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));

        await SelectFormatAsync(provider, "__custom__");

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-custom\"]").Should().NotBeNull());
    }

    [Fact]
    public async Task Preview_ShowsFormattedOutputForValidFormat_AndInvalidFormatFallback()
    {
        HotstringEditModel item = new() { Trigger = "d", DateTimeFormat = "yyyy", Kind = HotstringKind.DateTime };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-preview\"]").TextContent.Trim()
            .Should().Be(DateTime.Now.Year.ToString()));

        item.DateTimeFormat = "yyyy'unterminated";
        provider.Render();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-preview\"]").TextContent.Should().Contain("Invalid format"));
    }

    [Fact]
    public async Task OffsetSwitch_TogglingOnAndOff_AddsAndRemovesFieldsAndNullsDefaults()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));
        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"date-offset-switch\"]"));

        provider.FindAll("[data-test=\"date-offset-amount\"]").Should().BeEmpty();

        provider.Find("input[data-test=\"date-offset-switch\"]").Change(true);

        provider.WaitForAssertion(() =>
        {
            provider.Find("input[data-test=\"date-offset-amount\"]").GetAttribute("value").Should().Be("1");
            provider.Find("[data-test=\"date-offset-unit\"]").Should().NotBeNull();
        });

        provider.Find("input[data-test=\"date-offset-switch\"]").Change(false);

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"date-offset-amount\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task Save_WithDateTimeKind_PostsDtoWithEmptyReplacement()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "date", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));
        await SelectFormatAsync(provider, "yyyy-MM-dd");

        provider.Find("input[data-test=\"trigger-input\"]").Input("date");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.DateTime && d.Replacement == ""),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SwitchAwayFromDateTime_WithFormatSet_PromptsConfirmation()
    {
        // MudBlazor's IDialogService.ShowMessageBoxAsync opens a MudMessageBox rendered by the
        // same MudDialogProvider used for the edit dialog itself. bUnit renders it inline, so we
        // assert on the underlying model state (via a re-render probe) rather than trying to
        // synchronously await the nested dialog's result from the click handler.
        HotstringEditModel item = new() { Trigger = "date", Kind = HotstringKind.DateTime, DateTimeFormat = "yyyy-MM-dd" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click();

        // A confirmation MudMessageBox should now be present in the DOM (rendered by the same
        // MudDialogProvider), and the underlying model must remain untouched until it resolves.
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Switching to Text"));
        item.Kind.Should().Be(HotstringKind.DateTime);
        item.DateTimeFormat.Should().Be("yyyy-MM-dd");
    }

    [Fact]
    public async Task SwitchToDateTime_WithNonEmptyReplacement_PromptsConfirmation()
    {
        // Mirrors SwitchAwayFromDateTime_WithFormatSet_PromptsConfirmation for the opposite
        // direction: Text -> DateTime with a non-empty Replacement should prompt for
        // confirmation and leave the model untouched until it resolves.
        HotstringEditModel item = new() { Trigger = "btw", Kind = HotstringKind.Text, Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();

        // A confirmation MudMessageBox should now be present in the DOM (rendered by the same
        // MudDialogProvider), and the underlying model must remain untouched until it resolves.
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Switching to Date &amp; time"));
        item.Kind.Should().Be(HotstringKind.Text);
        item.Replacement.Should().Be("by the way");
    }

    [Fact]
    public async Task KindSelector_HasFourItemsIncludingMacroAndRaw()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();

        provider.WaitForAssertion(() =>
        {
            IReadOnlyList<AngleSharp.Dom.IElement> items = provider.FindAll(".mud-toggle-item");
            items.Should().HaveCount(4);
            items.Select(e => e.TextContent.Trim()).Should().Contain("Macro");
            items.Should().Contain(e => e.TextContent.Contains("Raw"));
        });
    }

    [Fact]
    public async Task MacroToolbar_HiddenForTextAndDateTime_VisibleForMacro()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll("[data-test=\"macro-toolbar\"]").Should().BeEmpty();

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));
        provider.FindAll("[data-test=\"macro-toolbar\"]").Should().BeEmpty();

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Macro").Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-toolbar\"]").Should().NotBeNull());
    }

    [Theory]
    [InlineData("Cursor", "{{cursor}}")]
    [InlineData("Enter", "{{key:Enter}}")]
    [InlineData("Tab", "{{key:Tab}}")]
    public async Task MacroToolbar_ClickInsertButton_InvokesCaretInsertionWithCanonicalToken(string buttonLabel, string expectedToken)
    {
        // MudTextField.InsertTextAtCurrentCaretPositionAsync mutates the real DOM element via JS interop
        // and relies on a browser "oninput" event to flow the change back into @bind-Value. bUnit's
        // JSInterop.Mode = Loose accepts the call but never mutates the DOM or raises that event, so
        // Item.Replacement can never observably change in this test environment. Instead, verify the
        // toolbar button triggers the caret-insertion JS interop call with the correct token.
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-toolbar\"]"));

        provider.FindAll("[data-test=\"macro-toolbar\"] button").First(b => b.TextContent.Contains(buttonLabel)).Click();

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("mudInput.insertAtCurrentCaretPosition");
            invocation.Arguments.Should().Contain(expectedToken);
        });
    }

    [Fact]
    public async Task MacroSuggestion_AppearsForTextWithToken_DismissesAndSwitches()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Text, Replacement = "Hi {{cursor}} bye" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-suggestion\"]").Should().NotBeNull());

        // Switching to Macro directly via the suggestion button (no confirm expected)
        provider.Find("[data-test=\"macro-suggestion\"] button").Click();

        provider.WaitForAssertion(() => item.Kind.Should().Be(HotstringKind.Macro));
    }

    [Fact]
    public async Task MacroSuggestion_DoesNotAppearWithoutToken()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Text, Replacement = "plain text" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll("[data-test=\"macro-suggestion\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task MacroSuggestion_DismissButton_HidesAlert()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Text, Replacement = "Hi {{cursor}} bye" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-suggestion\"]"));

        provider.Find("[data-test=\"macro-suggestion\"] button.mud-icon-button").Click();

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"macro-suggestion\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task SwitchFromMacroWithToken_ToText_PromptsConfirmation()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "Hi {{cursor}} bye" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Switch to Text"));
        item.Kind.Should().Be(HotstringKind.Macro);
        item.Replacement.Should().Be("Hi {{cursor}} bye");
    }

    [Fact]
    public async Task SwitchFromMacroWithoutToken_ToText_NoConfirmationNeeded()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "plain text" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click();

        provider.WaitForAssertion(() => item.Kind.Should().Be(HotstringKind.Text));
        item.Replacement.Should().Be("plain text");
    }

    [Fact]
    public async Task SwitchFromDateTime_ToMacro_WithFormatSet_PromptsConfirmation()
    {
        HotstringEditModel item = new() { Trigger = "date", Kind = HotstringKind.DateTime, DateTimeFormat = "yyyy-MM-dd" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Macro").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Switch to Macro"));
        item.Kind.Should().Be(HotstringKind.DateTime);
        item.DateTimeFormat.Should().Be("yyyy-MM-dd");
    }

    [Fact]
    public async Task SwitchFromText_ToMacro_NoConfirmationNeeded()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Text, Replacement = "plain text" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Macro").Click();

        provider.WaitForAssertion(() => item.Kind.Should().Be(HotstringKind.Macro));
        item.Replacement.Should().Be("plain text");
    }

    [Fact]
    public async Task PreviewPanel_Expand_TriggersExactlyOnePreviewCall()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("::btw::by the way")));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("::btw::by the way"));
        _ = _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task PreviewPanel_Collapsed_NeverCallsPreviewEvenAfterFieldChanges()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));

        provider.Find("input[data-test=\"trigger-input\"]").Input("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        provider.Render();

        _ = _api.DidNotReceive().PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task PreviewPanel_FieldChangeWhileExpanded_RecallsAfterDebounceWithUpdatedValues()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet")));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way"), Arg.Any<CancellationToken>()));

        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way!"), Arg.Any<CancellationToken>()),
            timeout: TimeSpan.FromSeconds(2));
    }

    [Fact]
    public async Task PreviewPanel_ValidationFailure_ShowsErrorMessageInsteadOfSnippet()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Replacement"] = ["Replacement is required."] })));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Replacement is required."));
    }

    [Fact]
    public async Task PreviewPanel_OutOfOrderResponses_LaterGenerationWins()
    {
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs1 = new();
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs2 = new();

        _api.PreviewAsync(Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "one"), Arg.Any<CancellationToken>())
            .Returns(tcs1.Task);
        _api.PreviewAsync(Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "two"), Arg.Any<CancellationToken>())
            .Returns(tcs2.Task);

        HotstringEditModel item = new() { Trigger = "one", Replacement = "text" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "one"), Arg.Any<CancellationToken>()));

        provider.Find("input[data-test=\"trigger-input\"]").Input("two");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "two"), Arg.Any<CancellationToken>()));

        // Resolve the newer (generation 2) response first, then the stale (generation 1) response.
        // The stale response must never overwrite the newer result.
        tcs2.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet-two")));
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("snippet-two"));

        tcs1.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet-one")));
        await Task.Delay(150);
        provider.Render();

        provider.Markup.Should().Contain("snippet-two");
        provider.Markup.Should().NotContain("snippet-one");
    }

    [Fact]
    public async Task PreviewPanel_CollapseCancelsPendingPreview_NoErrorSurfaced()
    {
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(tcs.Task);

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        // Collapse while the preview call is still pending.
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        tcs.SetException(new OperationCanceledException());

        await Task.Delay(150);
        provider.Render();

        provider.FindAll(".mud-alert").Should().BeEmpty();
    }

    [Fact]
    public async Task PreviewPanel_DisposeCancelsPendingPreview_NoUnhandledException()
    {
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(tcs.Task);

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        await DisposeAsync();

        Func<Task> act = async () =>
        {
            tcs.SetException(new OperationCanceledException());
            await Task.Delay(150);
        };

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task PreviewPanel_TypingWithoutBlur_SendsUpdatedValueToPreview()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet")));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way"), Arg.Any<CancellationToken>()));

        // Raise input events only — the field never blurs, so a change-on-blur binding
        // would keep sending the stale value.
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!!");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way!!"), Arg.Any<CancellationToken>()));

        provider.Find("input[data-test=\"trigger-input\"]").Input("btw2");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "btw2"), Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task PreviewPanel_LateResponseIgnoringCancellation_NeverSurfacesEvenAfterReopen()
    {
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs1 = new();
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs2 = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(tcs1.Task, tcs2.Task);

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        // Collapse, then let the first transport "ignore" cancellation and complete successfully.
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        tcs1.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("sneaky-snippet")));

        await Task.Delay(100);
        provider.Render();
        provider.Markup.Should().NotContain("sneaky-snippet");

        // Reopen: a fresh preview call starts (tcs2, still pending) — the stale response
        // must not have been stashed in hidden state.
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();
        provider.WaitForAssertion(() => _api.Received(2).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        provider.Markup.Should().NotContain("sneaky-snippet");
    }

    [Fact]
    public async Task PreviewPanel_WhilePending_ShowsUpdatingIndicator_ThenSnippet()
    {
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(tcs.Task);

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"preview-pending\"]").TextContent.Should().Contain("Updating preview"));

        tcs.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet-x")));

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("[data-test=\"preview-pending\"]").Should().BeEmpty();
            provider.Find("[data-test=\"preview-snippet\"]").TextContent.Should().Contain("snippet-x");
            provider.Find("[data-test=\"preview-snippet\"]").ClassList.Should().NotContain("preview-stale");
        });
    }

    [Fact]
    public async Task PreviewPanel_UnexpectedFault_ClearsPendingAndShowsFriendlyError()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns<ApiResult<HotstringPreviewDto>>(_ => throw new InvalidOperationException("boom - e.g. a deserialization failure"));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("[data-test=\"preview-pending\"]").Should().BeEmpty(
                "an unexpected fault must not leave the spinner stuck forever");
            provider.Find("[data-test=\"preview-error\"]").TextContent.Should().NotBeNullOrWhiteSpace();
        });
    }

    [Fact]
    public async Task PreviewPanel_WhileRefreshing_KeepsPreviousSnippetVisiblyDimmed()
    {
        TaskCompletionSource<ApiResult<HotstringPreviewDto>> tcs2 = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet-one"))), tcs2.Task);

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "one" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"preview-snippet\"]").TextContent.Should().Contain("snippet-one"));

        provider.Find("textarea[data-test=\"replacement-input\"]").Input("two");

        // The previous snippet stays visible but is explicitly marked stale while the
        // refresh is in flight — never presented as current.
        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"preview-pending\"]").TextContent.Should().Contain("Updating preview");
            provider.Find("[data-test=\"preview-snippet\"]").ClassList.Should().Contain("preview-stale");
            provider.Find("[data-test=\"preview-snippet\"]").TextContent.Should().Contain("snippet-one");
            provider.Find("[data-test=\"preview-copy\"]").HasAttribute("disabled").Should().BeTrue();
        });
    }

    [Fact]
    public async Task PreviewPanel_CopyButton_CopiesSnippetAndShowsSnackbar()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("::btw::by the way")));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"preview-copy\"]"));
        provider.Find("[data-test=\"preview-copy\"]").GetAttribute("aria-label").Should().NotBeNullOrEmpty();
        provider.Find("[data-test=\"preview-copy\"]").Click();

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("navigator.clipboard.writeText");
            invocation.Arguments.Should().Contain("::btw::by the way");
            _snackbar.Received(1).Add("Generated code copied.", Severity.Success, Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());
        });
    }

    [Fact]
    public async Task PreviewPanel_RendersDirectlyAfterEditor_BeforeDescription()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "x" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));

        string markup = provider.Markup;
        int toolbar = markup.IndexOf("data-test=\"macro-toolbar\"", StringComparison.Ordinal);
        int replacement = markup.IndexOf("data-test=\"replacement-input\"", StringComparison.Ordinal);
        int preview = markup.IndexOf("data-test=\"ahk-preview\"", StringComparison.Ordinal);
        int description = markup.IndexOf("data-test=\"description-input\"", StringComparison.Ordinal);

        toolbar.Should().BePositive().And.BeLessThan(replacement, "the insert toolbar sits above the Replacement editor");
        replacement.Should().BeLessThan(preview, "the preview panel sits directly below the editor");
        preview.Should().BeLessThan(description, "the preview panel comes before Description");
    }

    [Fact]
    public async Task PreviewPanel_ValidationError_MapsToReplacementFieldOnly_NoPanelDuplicate()
    {
        const string parserMessage = "Unknown token '{{key:Escape}}'. Allowed: {{cursor}}, {{key:Enter}}, {{key:Tab}}.";
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.Replacement"] = [parserMessage] })));

        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "{{key:Escape}}" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> replacementField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Replacement").Instance;
            replacementField.GetState(x => x.ErrorText).Should().Be(parserMessage, "the DTO property-path prefix must be stripped");

            provider.FindAll("[data-test=\"preview-error\"]").Should().BeEmpty(
                "a field-mapped error shows inline only, never duplicated in the panel");
        });
    }

    [Fact]
    public async Task PreviewPanel_FieldError_ClearsImmediatelyWhenSchedulingNextPreview()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Replacement"] = ["Replacement is required."] })));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
            provider.FindComponents<MudTextField<string>>().Single(f => f.Instance.Label == "Replacement")
                .Instance.GetState(x => x.ErrorText).Should().Be("Replacement is required."));

        TaskCompletionSource<ApiResult<HotstringPreviewDto>> pending = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()).Returns(pending.Task);

        provider.Find("textarea[data-test=\"replacement-input\"]").Input("fixed");

        provider.WaitForAssertion(() =>
            provider.FindComponents<MudTextField<string>>().Single(f => f.Instance.Label == "Replacement")
                .Instance.GetState(x => x.ErrorText).Should().BeNullOrEmpty(
                    "the stale field error must not linger while a corrected value awaits its next preview"));
    }

    [Fact]
    public async Task PreviewPanel_TriggerValidationError_MapsToTriggerField()
    {
        const string triggerMessage = "Trigger is required.";
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.Trigger"] = [triggerMessage] })));

        HotstringEditModel item = new() { Trigger = "", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> triggerField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Trigger").Instance;
            triggerField.GetState(x => x.ErrorText).Should().Be(triggerMessage);
        });
    }

    [Fact]
    public async Task MacroToolbar_ShowsInsertLabelAndHelperText()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"macro-toolbar\"]").TextContent.Should().Contain("Insert:");
            provider.Markup.Should().Contain("Enter/Tab must come before it");
        });
    }

    [Fact]
    public async Task MacroToolbar_CursorButton_DisabledWhenCursorTokenPresent()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "Hi {{cursor}}" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-toolbar\"]"));

        AngleSharp.Dom.IElement cursorButton = provider.FindAll("[data-test=\"macro-toolbar\"] button")
            .First(b => b.TextContent.Contains("Cursor"));

        cursorButton.HasAttribute("disabled").Should().BeTrue();
    }

    [Fact]
    public async Task MacroToolbar_EnterAfterCursor_BlockedWithInlineHint()
    {
        JSInterop.Setup<int>("mudInput.getCaretPosition", _ => true).SetResult(12);

        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "{{cursor}}tail" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-toolbar\"]"));

        provider.FindAll("[data-test=\"macro-toolbar\"] button").First(b => b.TextContent.Contains("Enter")).Click();

        provider.WaitForAssertion(() =>
            provider.Find("[data-test=\"macro-insert-hint\"]").TextContent.Should().Contain("before the {{cursor}} token"));
        JSInterop.Invocations.Should().NotContain(i => i.Identifier == "mudInput.insertAtCurrentCaretPosition");
    }

    [Fact]
    public async Task MacroToolbar_EnterBeforeCursor_InsertsToken()
    {
        JSInterop.Setup<int>("mudInput.getCaretPosition", _ => true).SetResult(0);

        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "abc{{cursor}}" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-toolbar\"]"));

        provider.FindAll("[data-test=\"macro-toolbar\"] button").First(b => b.TextContent.Contains("Enter")).Click();

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("mudInput.insertAtCurrentCaretPosition");
            invocation.Arguments.Should().Contain("{{key:Enter}}");
        });
        provider.FindAll("[data-test=\"macro-insert-hint\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task ContextSwitch_TurnedOn_ShowsMatchTypeAndValueFields()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
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
    public async Task ContextSwitch_TurnedOff_ClearsContextFields()
    {
        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-value-input\"]"));
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
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);

        provider.WaitForAssertion(() =>
            provider.Find("input[data-test=\"context-value-input\"]").GetAttribute("placeholder").Should().Be("notepad.exe"));
    }

    [Fact]
    public async Task Save_WithContext_SendsContextInCreateDto()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"trigger-input\"]").Input("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.ContextMatchType == WindowMatchType.Executable && d.ContextValue == "notepad.exe"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Save_ContextOnEmptyValue_BlockedByValidation()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"context-switch\"]"));

        provider.Find("input[data-test=\"trigger-input\"]").Input("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        // Value field left empty while context is on.
        provider.Find("button.commit-edit").Click();

        await Task.Delay(150);
        provider.Render();

        _ = _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task PreviewRequest_ContextChanged_TriggersNewPreview()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet")));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.ContextMatchType == null), Arg.Any<CancellationToken>()));

        provider.Find("input[data-test=\"context-switch\"]").Change(true);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe");

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.ContextMatchType == WindowMatchType.Executable && r.ContextValue == "notepad.exe"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task ApplyPreviewResult_ContextValueError_ShownInlineNotInPanel()
    {
        const string contextMessage = "ContextValue must not contain double-quote characters.";
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.ContextValue"] = [contextMessage] })));

        HotstringEditModel item = new()
        {
            Trigger = "btw",
            Replacement = "by the way",
            ContextMatchType = WindowMatchType.Executable,
            ContextValue = "note\"pad.exe",
        };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> valueField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Value").Instance;
            valueField.GetState(x => x.ErrorText).Should().Be(contextMessage);

            provider.FindAll("[data-test=\"preview-error\"]").Should().BeEmpty(
                "a field-mapped context error shows inline only, never duplicated in the panel");
        });
    }

    [Fact]
    public async Task KindToggle_SelectRaw_ShowsPersistentWarningAlert()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Raw")).Click();

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"script-warning\"]").TextContent
                .Should().Contain("verbatim AutoHotkey definition");
            provider.FindAll("[data-test=\"script-warning\"] button").Should().BeEmpty(
                "the raw warning is persistent and must not offer a dismiss control");
        });
    }

    [Fact]
    public async Task KindToggle_SelectRaw_AppliesMonospaceClass()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.Markup.Should().NotContain("ahk-mono");

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Raw")).Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("ahk-mono"));
    }

    [Fact]
    public async Task KindToggle_TextToRaw_PromptsConfirmationAndKeepsFieldsUntilConfirmed()
    {
        // Text -> Raw with non-empty Replacement prompts a confirmation before wrapping the text
        // into a full definition — nothing must change ahead of that confirmation resolving.
        HotstringEditModel item = new() { Trigger = "ver", Kind = HotstringKind.Text, Replacement = "MsgBox 1" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Raw")).Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Switch to Raw"));
        item.Kind.Should().Be(HotstringKind.Text);
        item.Replacement.Should().Be("MsgBox 1");
    }

    [Fact]
    public async Task KindToggle_RawToText_DecomposesDefinitionIntoFields()
    {
        // A plain Raw definition (no options the structured fields can't express) decomposes
        // straight into Trigger + body with no confirmation.
        HotstringEditModel item = new() { Trigger = "ver", Kind = HotstringKind.Raw, Replacement = "::ver::\n{\nMsgBox 1\n}" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click();

        provider.WaitForAssertion(() =>
        {
            item.Kind.Should().Be(HotstringKind.Text);
            item.Trigger.Should().Be("ver");
            item.Replacement.Should().Be("MsgBox 1");
        });
    }

    [Fact]
    public async Task ScriptSuggestion_TextLooksLikeCode_ShowsDismissibleAlert()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Text, Replacement = "Send \"{Enter}\"" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"script-suggestion\"]").Should().NotBeNull());

        provider.Find("[data-test=\"script-suggestion\"] button.mud-icon-button").Click();

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"script-suggestion\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task Suggestions_ReplacementHasMacroToken_ShowsMacroSuggestionOnly()
    {
        // A recognized macro token contains braces, so LooksLikeAhkCode alone would also flag it
        // as Script-like. Macro tokens must take precedence: only the Macro suggestion shows.
        HotstringEditModel item = new() { Trigger = "hi", Kind = HotstringKind.Text, Replacement = "Hi {{cursor}}" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"macro-suggestion\"]").Should().NotBeNull());
        provider.FindAll("[data-test=\"script-suggestion\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Save_RawKind_SendsDefinitionVerbatimInCreateDto()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "ftw", ":K1000 SE*:ftw::for the win", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, [], HotstringKind.Raw);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":K1000 SE*:ftw::for the win" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("button.commit-edit"));

        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.Raw && d.Replacement == ":K1000 SE*:ftw::for the win"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task PreviewError_RawBraceImbalance_ShownInlineOnRawDefinitionField()
    {
        const string braceMessage = "Raw definition must have balanced braces.";
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.Replacement"] = [braceMessage] })));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":*:m::\n{\nSend foo" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));
        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> replacementField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Raw definition").Instance;
            replacementField.GetState(x => x.ErrorText).Should().Be(braceMessage);
        });
    }

    [Fact]
    public async Task Save_RawBraceImbalance_WithPreviewCollapsed_ShowsInlineRawDefinitionError()
    {
        const string braceMessage = "Raw definition must have balanced braces.";
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Validation,
                new ApiProblemDetails(null, "Bad Request", 400, null, null,
                    new Dictionary<string, string[]> { ["Input.Replacement"] = [braceMessage] })));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":*:m::\n{\nSend foo" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("button.commit-edit"));

        // Preview panel is never expanded — this exercises SaveAsync's own field-error mapping,
        // not ApplyPreviewResult's.
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> replacementField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Raw definition").Instance;
            replacementField.GetState(x => x.ErrorText).Should().Be(braceMessage);

            provider.FindAll(".mud-alert").Should().NotContain(e => e.TextContent.Contains(braceMessage),
                "a field-mapped save error shows inline only, never duplicated in an alert");
        });
    }

    [Fact]
    public async Task RawKind_PreviewCollapsed_AutoRequestsPreviewAndShowsParsedSummary()
    {
        // Raw's parsed trigger/options summary must appear below the textarea by default — the
        // preview runs even while the "Generated AutoHotkey code" panel stays collapsed.
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto(
                ":K1000 SE*:ftw::for the win",
                new RawSummaryDto("ftw", ["K1000", "SE", "*"], RawBodyKind.Inline, 0, null))));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":K1000 SE*:ftw::for the win" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);

        provider.WaitForAssertion(() =>
        {
            _ = _api.Received().PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>());
            provider.Find("[data-test=\"raw-summary\"]").TextContent.Should().Contain("ftw");
            provider.Find("[data-test=\"raw-summary\"]").TextContent.Should().Contain("K1000");
        });
    }

    [Fact]
    public async Task RawExamples_RenderPreviewTextBelowDefinition()
    {
        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = "" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement examples = provider.Find("[data-test=\"raw-templates\"]");
            examples.TextContent.Should().Contain("Examples");
            examples.TextContent.Should().Contain(":*:col::  ( red / green / blue )");
        });
    }

    [Theory]
    [InlineData(HotstringDelivery.Auto)]
    [InlineData(HotstringDelivery.ClipboardPaste)]
    public async Task Save_LongTextReplacement_AllowsAutoAndClipboardDelivery(HotstringDelivery delivery)
    {
        string replacement = new('x', 4_001);
        HotstringEditModel item = new()
        {
            Trigger = "long",
            Replacement = "initial",
            Delivery = delivery,
        };
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(Guid.NewGuid(), [], true, "long", replacement, null, true, true,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, Delivery: delivery)));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("textarea[data-test=\"replacement-input\"]"));
        provider.Find("textarea[data-test=\"replacement-input\"]").Input(replacement);
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(dto => dto.Replacement.Length == 4_001 && dto.Delivery == delivery),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task DeliverySelector_TextOnly_ShowsHintAndResetsWhenKindChanges()
    {
        HotstringEditModel item = new()
        {
            Trigger = "long",
            Replacement = "",
            Delivery = HotstringDelivery.ClipboardPaste,
        };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"delivery-select\"]"));
        provider.Markup.Should().Contain("Auto types short replacements and pastes 200+ characters via the clipboard");

        IRenderedComponent<MudToggleGroup<HotstringKind>> kindSelector = provider.FindComponent<MudToggleGroup<HotstringKind>>();
        await provider.InvokeAsync(() => kindSelector.Instance.ValueChanged.InvokeAsync(HotstringKind.Macro));

        provider.WaitForAssertion(() =>
        {
            item.Delivery.Should().Be(HotstringDelivery.Auto);
            provider.FindAll("[data-test=\"delivery-select\"]").Should().BeEmpty();
        });
    }

    [Fact]
    public async Task RawExample_CopyButton_CopiesTemplateAndLeavesDefinitionUntouched()
    {
        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":*:custom::my own text" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"raw-template-inline\"]"));

        provider.Find("[data-test=\"raw-template-inline\"]").Click();

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("navigator.clipboard.writeText");
            invocation.Arguments.Should().Contain(":*:btw::by the way");
            _snackbar.Received(1).Add("Example copied — paste it into the definition.", Severity.Success,
                Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());
        });
        // Copy is a reference action — the user's own definition is never overwritten.
        item.Replacement.Should().Be(":*:custom::my own text");
    }

    [Fact]
    public async Task RawExample_CopyButton_CopiesMultiLineTemplateVerbatim()
    {
        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = "" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"raw-template-continuation\"]"));

        provider.Find("[data-test=\"raw-template-continuation\"]").Click();

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("navigator.clipboard.writeText");
            invocation.Arguments.Should().Contain(":*:col::\n(\nred\ngreen\nblue\n)");
        });
    }

    [Fact]
    public async Task RawSummary_ShowsBodyKindAndCommentLiftNotice()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto(
                "; note\n:*:col::\n(\nred\ngreen\nblue\n)",
                new RawSummaryDto("col", ["*"], RawBodyKind.Continuation, 3, "note"))));

        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = "; note\n:*:col::\n(\nred\ngreen\nblue\n)" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"raw-summary\"]").TextContent.Should().Contain("multi-line text (3 lines)");
            provider.Find("[data-test=\"raw-comment-lift\"]").TextContent.Should().Contain("Comment will be added to Description: note");
        });
    }

    [Fact]
    public async Task PreviewPanel_ShowsEffectiveClipboardDelivery_AndSendsSelectedDelivery()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(
                new HotstringPreviewDto("snippet", EffectiveDelivery: HotstringDelivery.ClipboardPaste)));
        HotstringEditModel item = new()
        {
            Trigger = "long",
            Replacement = new string('x', 200),
            Delivery = HotstringDelivery.Auto,
        };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"preview-delivery\"]").TextContent.Should().Contain("Clipboard");
            _ = _api.Received().PreviewAsync(
                Arg.Is<HotstringPreviewRequestDto>(request => request.Delivery == HotstringDelivery.Auto),
                Arg.Any<CancellationToken>());
        });
    }

    [Fact]
    public async Task PreviewPanel_ShowsEffectiveTypedDeliveryAsHotstring()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(
                new HotstringPreviewDto("snippet", EffectiveDelivery: HotstringDelivery.Type)));
        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"preview-delivery\"]").TextContent.Should().Contain("Hotstring");
        });
    }

    [Theory]
    [InlineData(HotstringKind.Macro)]
    [InlineData(HotstringKind.DateTime)]
    [InlineData(HotstringKind.Raw)]
    public async Task PreviewPanel_NonTextKind_HidesDeliveryChip(HotstringKind kind)
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(
                new HotstringPreviewDto("snippet", EffectiveDelivery: HotstringDelivery.Type)));
        HotstringEditModel item = kind switch
        {
            HotstringKind.Macro => new() { Kind = kind, Trigger = "macro", Replacement = "value" },
            HotstringKind.DateTime => new() { Kind = kind, Trigger = "date", DateTimeFormat = "yyyy-MM-dd" },
            HotstringKind.Raw => new() { Kind = kind, Replacement = "::raw::value" },
            _ => throw new ArgumentOutOfRangeException(nameof(kind)),
        };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);

        provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click();

        provider.WaitForAssertion(() =>
        {
            _ = _api.Received().PreviewAsync(
                Arg.Is<HotstringPreviewRequestDto>(request => request.Kind == kind),
                Arg.Any<CancellationToken>());
            provider.FindAll("[data-test=\"preview-delivery\"]").Should().BeEmpty();
        });
    }

    private static void DisablePreviewDebounce(IRenderedComponent<MudDialogProvider> provider) =>
        provider.FindComponent<HotstringEditDialog>().Instance.PreviewDebounce = TimeSpan.Zero;

    private async Task<IRenderedComponent<MudDialogProvider>> RenderDialogAsync(HotstringEditModel? item = null)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };
            if (item is not null)
                parameters[nameof(HotstringEditDialog.Item)] = item;

            await dialogService.ShowAsync<HotstringEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    private static Task SelectFormatAsync(IRenderedComponent<MudDialogProvider> provider, string format) =>
        provider.InvokeAsync(() =>
            provider.FindComponent<MudSelect<string>>().Instance.ValueChanged.InvokeAsync(format));
}
