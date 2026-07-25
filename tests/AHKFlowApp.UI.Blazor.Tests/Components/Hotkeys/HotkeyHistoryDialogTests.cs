using AHKFlowApp.UI.Blazor.Components.Hotkeys;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotkeys;

public sealed class HotkeyHistoryDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    private readonly Guid _id = Guid.NewGuid();

    public HotkeyHistoryDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());
        Services.AddMudServices();
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
            await dialogService.ShowAsync<HotkeyHistoryDialog>(
                "History",
                new DialogParameters
                {
                    [nameof(HotkeyHistoryDialog.HotkeyId)] = _id,
                    [nameof(HotkeyHistoryDialog.Description)] = "Open Notepad",
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

    private static HotkeySnapshot RunSnapshot() =>
        new(
            "Open Notepad",
            "F9",
            true,
            false,
            false,
            false,
            HotkeyActionKind.Run,
            null,
            null,
            "notepad.exe",
            RunTargetKind.Application,
            null,
            null,
            null,
            true,
            [],
            [],
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow);

    private void StubOneVersion(HotkeySnapshot snapshot)
    {
        _api.GetHistoryAsync(_id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HistoryEntryDto[]>.Ok([new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)]));
        _api.GetHistoryVersionAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyHistoryVersionDto>.Ok(
                new HotkeyHistoryVersionDto(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow, snapshot)));
    }

    [Fact]
    public async Task Dialog_TypedSnapshot_ShowsKindLabelAndSummary()
    {
        StubOneVersion(RunSnapshot());

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        await provider.InvokeAsync(() => provider.Find("button.history-version").Click());

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Run"));
        provider.Markup.Should().Contain("notepad.exe");
    }

    [Fact]
    public async Task Dialog_LegacySnapshot_FallsBackToActionAndParameters()
    {
        // Old history JSON predates the typed action fields: it only carries the Action /
        // Parameters pair, and its ActionKind deserializes to the record's default — Raw — which
        // is exactly the wire shape the backend replays (no legacy conversion on read). The
        // dialog must not present such a row as a Raw script.
        StubOneVersion(RunSnapshot() with
        {
            ActionKind = HotkeyActionKind.Raw,
            RunTarget = null,
            RunTargetKind = null,
            Action = HotkeyAction.Run,
            Parameters = "legacy.exe",
        });

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        await provider.InvokeAsync(() => provider.Find("button.history-version").Click());

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Legacy"));
        provider.Markup.Should().Contain("Run legacy.exe");
        provider.Markup.Should().NotContain(HotkeyActionDisplay.Label(HotkeyActionKind.Raw));
    }

    [Fact]
    public async Task Dialog_SelectVersionAndRevert_CallsRevertApi()
    {
        StubOneVersion(RunSnapshot());
        _api.RevertAsync(_id, 1, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(
                new HotkeyDto(
                    _id,
                    [],
                    true,
                    "Open Notepad",
                    "F9",
                    true,
                    false,
                    false,
                    false,
                    HotkeyActionKind.Run,
                    null,
                    null,
                    "notepad.exe",
                    RunTargetKind.Application,
                    null,
                    null,
                    null,
                    DateTimeOffset.UtcNow,
                    DateTimeOffset.UtcNow,
                    [])));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("v1"));

        await provider.InvokeAsync(() => provider.Find("button.history-version").Click());
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("F9"));
        provider.Find("button.revert-version").HasAttribute("disabled").Should().BeFalse(provider.Markup);

        await provider.InvokeAsync(() => provider.Find("button.revert-version").Click());
        provider.WaitForAssertion(() =>
            _api.Received(1).RevertAsync(_id, 1, Arg.Any<CancellationToken>()));
    }
}
