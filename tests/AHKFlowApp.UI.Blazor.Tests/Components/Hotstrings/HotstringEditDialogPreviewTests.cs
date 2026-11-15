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

public sealed class HotstringEditDialogPreviewTests : HotstringEditDialogTestsBase
{
    [Fact]
    public async Task Preview_ShowsFormattedOutputForValidFormat_AndInvalidFormatFallback()
    {
        HotstringEditModel item = new() { Trigger = "d", DateTimeFormat = "yyyy", Kind = HotstringKind.DateTime };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-preview\"]").TextContent.Trim()
            .Should().Be("2031"));

        item.DateTimeFormat = "yyyy'unterminated";
        provider.Render();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-preview\"]").TextContent.Should().Contain("Invalid format"));
    }

    [Fact]
    public async Task PreviewPanel_Expand_TriggersExactlyOnePreviewCall()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("::btw::by the way")));

        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"ahk-preview\"]"));

        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("::btw::by the way"));
        _ = _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task PreviewPanel_Collapsed_NeverCallsPreviewEvenAfterFieldChanges()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        DisablePreviewDebounce(provider);
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw"));
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way"));
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way"), Arg.Any<CancellationToken>()));

        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!"));

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

        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "one"), Arg.Any<CancellationToken>()));

        // Capture generation 1's run before generation 2 replaces the handle.
        Task staleRun = PreviewRun(provider);

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("two"));

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Trigger == "two"), Arg.Any<CancellationToken>()));

        // Resolve the newer (generation 2) response first, then the stale (generation 1) response.
        // The stale response must never overwrite the newer result.
        tcs2.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet-two")));
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("snippet-two"));

        tcs1.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("snippet-one")));
        await staleRun;
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        Task run = PreviewRun(provider);

        // Collapse while the preview call is still pending.
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        tcs.SetException(new OperationCanceledException());

        await run;
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        // Capture the run before disposal; the component is gone afterwards.
        Task run = PreviewRun(provider);

        await DisposeAsync();

        Func<Task> act = async () =>
        {
            tcs.SetException(new OperationCanceledException());
            await run;
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way"), Arg.Any<CancellationToken>()));

        // Raise input events only — the field never blurs, so a change-on-blur binding
        // would keep sending the stale value.
        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!!"));

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.Replacement == "by the way!!"), Arg.Any<CancellationToken>()));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"trigger-input\"]").Input("btw2"));

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()));

        Task run = PreviewRun(provider);

        // Collapse, then let the first transport "ignore" cancellation and complete successfully.
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());
        tcs1.SetResult(ApiResult<HotstringPreviewDto>.Ok(new HotstringPreviewDto("sneaky-snippet")));

        await run;
        provider.Render();
        provider.Markup.Should().NotContain("sneaky-snippet");

        // Reopen: a fresh preview call starts (tcs2, still pending) — the stale response
        // must not have been stashed in hidden state.
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => provider.Find("[data-test=\"preview-snippet\"]").TextContent.Should().Contain("snippet-one"));

        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("two"));

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => provider.Find("[data-test=\"preview-copy\"]"));
        provider.Find("[data-test=\"preview-copy\"]").GetAttribute("aria-label").Should().NotBeNullOrEmpty();
        await provider.InvokeAsync(() => provider.Find("[data-test=\"preview-copy\"]").Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() =>
            provider.FindComponents<MudTextField<string>>().Single(f => f.Instance.Label == "Replacement")
                .Instance.GetState(x => x.ErrorText).Should().Be("Replacement is required."));

        TaskCompletionSource<ApiResult<HotstringPreviewDto>> pending = new();
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>()).Returns(pending.Task);

        await provider.InvokeAsync(() => provider.Find("textarea[data-test=\"replacement-input\"]").Input("fixed"));

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> triggerField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Trigger").Instance;
            triggerField.GetState(x => x.ErrorText).Should().Be(triggerMessage);
        });
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.ContextMatchType == null), Arg.Any<CancellationToken>()));

        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-switch\"]").Change(true));
        provider.WaitForAssertion(() => provider.Find("input[data-test=\"context-value-input\"]"));
        await provider.InvokeAsync(() => provider.Find("input[data-test=\"context-value-input\"]").Input("notepad.exe"));

        provider.WaitForAssertion(() => _api.Received(1).PreviewAsync(
            Arg.Is<HotstringPreviewRequestDto>(r => r.ContextMatchType == WindowMatchType.Executable && r.ContextValue == "notepad.exe"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task ApplyPreviewResult_ContextValueError_ShownInlineNotInPanel()
    {
        const string contextMessage = "Value under Window context must not contain double quotes.";
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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

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
        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() =>
        {
            MudTextField<string> replacementField = provider.FindComponents<MudTextField<string>>()
                .Single(f => f.Instance.Label == "Raw definition").Instance;
            replacementField.GetState(x => x.ErrorText).Should().Be(braceMessage);
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

        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() =>
        {
            provider.Find("[data-test=\"preview-delivery\"]").TextContent.Should().Contain("Clipboard");
            _ = _api.Received().PreviewAsync(
                Arg.Is<HotstringPreviewRequestDto>(request => request.Delivery == HotstringDelivery.Auto),
                Arg.Any<CancellationToken>());
        });
    }

    [Fact]
    public async Task PreviewPanel_ShowsEffectiveTypedDeliveryAsTyped()
    {
        _api.PreviewAsync(Arg.Any<HotstringPreviewRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringPreviewDto>.Ok(
                new HotstringPreviewDto("snippet", EffectiveDelivery: HotstringDelivery.Type)));
        HotstringEditModel item = new() { Trigger = "btw", Replacement = "by the way" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        DisablePreviewDebounce(provider);

        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() =>
        {
            // "Typed" replaced "Hotstring" here — CONTEXT.md lists the old label under Avoid,
            // because it overloaded the name of the whole entity.
            provider.Find("[data-test=\"preview-delivery\"]").TextContent.Should().Contain("Typed");
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

        await provider.InvokeAsync(() => provider.Find("[data-test=\"ahk-preview\"] .mud-expand-panel-header").Click());

        provider.WaitForAssertion(() =>
        {
            _ = _api.Received().PreviewAsync(
                Arg.Is<HotstringPreviewRequestDto>(request => request.Kind == kind),
                Arg.Any<CancellationToken>());
            provider.FindAll("[data-test=\"preview-delivery\"]").Should().BeEmpty();
        });
    }
}
