using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringHistoryDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();
    private readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();
    private readonly Guid _id = Guid.NewGuid();

    public HotstringHistoryDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();

        // Registered after AddMudServices so this substitute wins, which is what lets a test read
        // back the message the dialog showed.
        Services.AddSingleton(_snackbar);
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private async Task<IRenderedComponent<MudDialogProvider>> OpenDialogAsync()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringHistoryDialog>(
                "History",
                new DialogParameters
                {
                    [nameof(HotstringHistoryDialog.HotstringId)] = _id,
                    [nameof(HotstringHistoryDialog.Trigger)] = "btw",
                });
        });

        return provider;
    }

    [Fact]
    public async Task Dialog_RendersVersionsFromApi()
    {
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok(
                [new(2, HistoryChangeType.Edit, DateTimeOffset.UtcNow), new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v2"));
        provider.Markup.Should().Contain("v1");
    }

    [Fact]
    public async Task Dialog_NoHistory_ShowsEmptyMessage()
    {
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([]));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("No history yet"));
    }

    [Fact]
    public async Task Dialog_SelectVersionAndRevert_CallsRevertApi()
    {
        HotstringSnapshot snapshot = new(
            "btw",
            "old text",
            null,
            true,
            true,
            true,
            [],
            [],
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow);
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));
        _api.GetHistoryVersionAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringHistoryVersionDto>.Ok(
                new HotstringHistoryVersionDto(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow, snapshot)));
        _api.RevertAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(
                    _id,
                    [],
                    true,
                    "btw",
                    "old text",
                    null,
                    true,
                    true,
                    DateTimeOffset.UtcNow,
                    DateTimeOffset.UtcNow,
                    [])));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        await provider.InvokeAsync(() => provider.Find("button.history-version").Click());
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("old text"));
        provider.Find("button.revert-version").HasAttribute("disabled").Should().BeFalse(provider.Markup);

        await provider.InvokeAsync(() => provider.Find("button.revert-version").Click());
        provider.WaitForAssertion(() =>
            _api.Received(1).RevertAsync(_id, 1, Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Dialog_SelectDateTimeVersion_RendersFormatSummaryNotBlankReplacement()
    {
        HotstringSnapshot snapshot = new(
            "todaydate",
            "",
            null,
            true,
            true,
            true,
            [],
            [],
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow,
            HotstringKind.DateTime,
            "yyyy-MM-dd",
            1,
            DateOffsetUnit.Days);
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));
        _api.GetHistoryVersionAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringHistoryVersionDto>.Ok(
                new HotstringHistoryVersionDto(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow, snapshot)));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        await provider.InvokeAsync(() => provider.Find("button.history-version").Click());

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("yyyy-MM-dd (+1 day)"));
    }

    [Fact]
    public async Task Dialog_RevertRefusedByCurrentRules_ShowsTheRuleMessageAndStaysOpen()
    {
        // A Revert whose stored Snapshot fails a current rule returns 400 with the rule's own
        // message (backlog 162). The Owner has to read that message and pick another version, so
        // the dialog must stay open behind it.
        HotstringSnapshot snapshot = new(
            "btw", "old text", null, true, true, true, [], [],
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));
        _api.GetHistoryVersionAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringHistoryVersionDto>.Ok(
                new HotstringHistoryVersionDto(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow, snapshot)));
        _api.RevertAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(
                ApiResultStatus.Validation,
                new ApiProblemDetails(
                    Type: null, Title: "One or more validation errors occurred.",
                    Status: 400, Detail: null, Instance: null,
                    Errors: new Dictionary<string, string[]>
                    {
                        ["ContextValue"] = ["ContextValue must not contain double-quote characters."],
                    })));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        await provider.InvokeAsync(() => provider.Find("button.history-version").Click());
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("old text"));

        await provider.InvokeAsync(() => provider.Find("button.revert-version").Click());

        provider.WaitForAssertion(() => _snackbar.Received(1).Add(
            "ContextValue: ContextValue must not contain double-quote characters.",
            Severity.Error,
            Arg.Any<Action<SnackbarOptions>>(),
            Arg.Any<string>()));

        // Still open: a refused Revert leaves the version list where it was, so the Owner can
        // choose a different version without reopening the dialog.
        provider.FindAll("button.revert-version").Should().NotBeEmpty(
            "a refused Revert must not close the dialog");
    }

    // Backlog 168. The back-arrow button has no text, so its label says what it does.
    [Fact]
    public async Task CloseButton_NamesWhatItDoes()
    {
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([]));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() =>
            provider.Find("button.close-history").GetAttribute("aria-label").Should().Be("Close history"));
    }
}
