using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringEditDialogKindSwitchTests : HotstringEditDialogTestsBase
{
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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));

        await SelectFormatAsync(provider, "yyyy-MM-dd");

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("date"));
        await provider.InvokeAsync(() => provider.Find("button.commit-edit").Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));

        await SelectFormatAsync(provider, "__custom__");

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-custom\"]").Should().NotBeNull());
    }

    [Fact]
    public async Task OffsetSwitch_TogglingOnAndOff_AddsAndRemovesFieldsAndNullsDefaults()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));
        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());
        provider.WaitForAssertion(() => provider.Find("[data-test=\"date-offset-switch\"]"));

        provider.FindAll("[data-test=\"date-offset-amount\"]").Should().BeEmpty();

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"date-offset-switch\"]").Change(true));

        provider.WaitForAssertion(() =>
        {
            provider.Find("input[data-test=\"date-offset-amount\"]").GetAttribute("value").Should().Be("1");
            provider.Find("[data-test=\"date-offset-unit\"]").Should().NotBeNull();
        });

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"date-offset-switch\"]").Change(false));

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"date-offset-amount\"]").Should().BeEmpty());
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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click());
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));
        provider.FindAll("[data-test=\"macro-toolbar\"]").Should().BeEmpty();

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Macro").Click());
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

        await provider.InvokeAsync(() => provider.FindAll("[data-test=\"macro-toolbar\"] button").First(b => b.TextContent.Contains(buttonLabel)).Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"macro-suggestion\"] button").Click());

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

        await provider.InvokeAsync(() => provider.Find("[data-test=\"macro-suggestion\"] button.mud-icon-button").Click());

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"macro-suggestion\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task SwitchFromMacroWithToken_ToText_PromptsConfirmation()
    {
        HotstringEditModel item = new() { Trigger = "sig", Kind = HotstringKind.Macro, Replacement = "Hi {{cursor}} bye" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click());

        provider.WaitForAssertion(() => item.Kind.Should().Be(HotstringKind.Text));
        item.Replacement.Should().Be("plain text");
    }

    [Fact]
    public async Task SwitchFromDateTime_ToMacro_WithFormatSet_PromptsConfirmation()
    {
        HotstringEditModel item = new() { Trigger = "date", Kind = HotstringKind.DateTime, DateTimeFormat = "yyyy-MM-dd" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Macro").Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Macro").Click());

        provider.WaitForAssertion(() => item.Kind.Should().Be(HotstringKind.Macro));
        item.Replacement.Should().Be("plain text");
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

        await provider.InvokeAsync(() => provider.FindAll("[data-test=\"macro-toolbar\"] button").First(b => b.TextContent.Contains("Enter")).Click());

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

        await provider.InvokeAsync(() => provider.FindAll("[data-test=\"macro-toolbar\"] button").First(b => b.TextContent.Contains("Enter")).Click());

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("mudInput.insertAtCurrentCaretPosition");
            invocation.Arguments.Should().Contain("{{key:Enter}}");
        });
        provider.FindAll("[data-test=\"macro-insert-hint\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task KindToggle_SelectRaw_ShowsPersistentWarningAlert()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Raw")).Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Raw")).Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Raw")).Click());

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

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click());

        provider.WaitForAssertion(() =>
        {
            item.Kind.Should().Be(HotstringKind.Text);
            item.Trigger.Should().Be("ver");
            item.Replacement.Should().Be("MsgBox 1");
        });
    }

    // Backlog 161. One branch in OnKindChangedAsync serves Text, Macro, and Date & time, so the
    // destination kind is a theory column rather than a copied test body. Every row asserts all
    // four option fields: the bug dropped three of them and switched the fourth ON.
    [Theory]
    [InlineData(":*C:btw::by the way", "Text", HotstringKind.Text, false, false, true, false)]
    [InlineData("::btw::by the way", "Text", HotstringKind.Text, true, false, false, false)]
    [InlineData(":?O:btw::by the way", "Text", HotstringKind.Text, true, true, false, true)]
    // One definition carrying all four at once, which acceptance criterion 3 asks for by name.
    [InlineData(":*?CO:btw::by the way", "Text", HotstringKind.Text, false, true, true, true)]
    [InlineData(":*C:btw::by the way", "Macro", HotstringKind.Macro, false, false, true, false)]
    [InlineData(":*C:btw::by the way", "Date & time", HotstringKind.DateTime, false, false, true, false)]
    public async Task KindToggle_LeavingRaw_KeepsTheDefinitionsOptions(
        string definition, string toggleText, HotstringKind expectedKind,
        bool endingRequired, bool insideWord, bool caseSensitive, bool omitEnding)
    {
        HotstringEditModel item = new() { Trigger = "btw", Kind = HotstringKind.Raw, Replacement = definition };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains(toggleText)).Click());

        provider.WaitForAssertion(() =>
        {
            item.Kind.Should().Be(expectedKind);
            item.IsEndingCharacterRequired.Should().Be(endingRequired);
            item.IsTriggerInsideWord.Should().Be(insideWord);
            item.IsCaseSensitive.Should().Be(caseSensitive);
            item.OmitEndingCharacter.Should().Be(omitEnding);
        });
    }

    [Fact]
    public async Task KindToggle_RawWithUnexpressibleOptions_StillAsksBeforeDiscarding()
    {
        // K1000 and SE have no structured field, so the question must still be asked, and nothing
        // may change until it is answered. This one is a guard, not a red test: it passes before
        // this task too, and its job is to fail if the expressible set ever swallows everything.
        HotstringEditModel item = new() { Trigger = "ftw", Kind = HotstringKind.Raw, Replacement = ":K1000 SE:ftw::for the win" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click());

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Converting to Text"));
        item.Kind.Should().Be(HotstringKind.Raw);
    }

    [Fact]
    public async Task KindToggle_RawWithCancelTokenOnly_SwitchesWithoutAsking()
    {
        // The other side of the boundary. ':*0:' is expressible after this task, so saying it
        // would be discarded would be false, and the switch goes straight through.
        HotstringEditModel item = new() { Trigger = "btw", Kind = HotstringKind.Raw, Replacement = ":*0:btw::by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        await provider.InvokeAsync(() => provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click());

        provider.WaitForAssertion(() =>
        {
            item.Kind.Should().Be(HotstringKind.Text);
            item.IsEndingCharacterRequired.Should().BeTrue();
        });
        provider.Markup.Should().NotContain("Converting to Text");
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

    [Fact]
    public async Task RawExample_CopyButton_CopiesTemplateAndLeavesDefinitionUntouched()
    {
        HotstringEditModel item = new() { Kind = HotstringKind.Raw, Replacement = ":*:custom::my own text" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"raw-template-inline\"]"));

        await provider.InvokeAsync(() => provider.Find("[data-test=\"raw-template-inline\"]").Click());

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

        await provider.InvokeAsync(() => provider.Find("[data-test=\"raw-template-continuation\"]").Click());

        provider.WaitForAssertion(() =>
        {
            Bunit.JSRuntimeInvocation invocation = JSInterop.VerifyInvoke("navigator.clipboard.writeText");
            invocation.Arguments.Should().Contain(":*:col::\n(\nred\ngreen\nblue\n)");
        });
    }
}
