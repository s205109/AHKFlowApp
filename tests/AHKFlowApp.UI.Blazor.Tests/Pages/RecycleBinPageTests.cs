using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class RecycleBinPageTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _hotstrings = Substitute.For<IHotstringsApiClient>();
    private readonly IHotkeysApiClient _hotkeys = Substitute.For<IHotkeysApiClient>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public RecycleBinPageTests()
    {
        Services.AddSingleton(_hotstrings);
        Services.AddSingleton(_hotkeys);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<RecycleBin> RenderPage()
    {
        Render<MudPopoverProvider>();
        Render<MudDialogProvider>();
        return Render<RecycleBin>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private void StubDeleted(DeletedHotstringDto[] hotstrings, DeletedHotkeyDto[] hotkeys)
    {
        _hotstrings.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotstringDto[]>.Ok(hotstrings));
        _hotkeys.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotkeyDto[]>.Ok(hotkeys));
    }

    [Fact]
    public void Page_OnLoad_ShowsDeletedItemsFromBothApis()
    {
        DeletedHotstringDto hotstring = new(Guid.NewGuid(), "btw", "by the way", null, DateTimeOffset.UtcNow);
        DeletedHotkeyDto hotkey = new(Guid.NewGuid(), "Open Notepad", "N", true, true, false, false, DateTimeOffset.UtcNow.AddMinutes(-1));
        StubDeleted([hotstring], [hotkey]);

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("btw"));

        cut.Markup.Should().Contain("Open Notepad");
        cut.Markup.Should().Contain("Hotstring");
        cut.Markup.Should().Contain("Hotkey");
    }

    [Fact]
    public void Page_OnEmptyBin_ShowsEmptyMessage()
    {
        StubDeleted([], []);

        IRenderedComponent<RecycleBin> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("No deleted items."));
    }

    [Fact]
    public void Page_RestoreHotstring_CallsRestoreApiAndReloads()
    {
        DeletedHotstringDto deleted = new(Guid.NewGuid(), "brb", "be right back", null, DateTimeOffset.UtcNow);
        _hotstrings.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(
                ApiResult<DeletedHotstringDto[]>.Ok([deleted]),
                ApiResult<DeletedHotstringDto[]>.Ok([]));
        _hotkeys.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotkeyDto[]>.Ok([]));
        _hotstrings.RestoreAsync(deleted.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(deleted.Id, [], true, deleted.Trigger, deleted.Replacement, null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, [])));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("brb"));

        cut.Find("button.restore-item").Click();

        cut.WaitForAssertion(() =>
            _hotstrings.Received(1).RestoreAsync(deleted.Id, Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() =>
            _hotstrings.Received(2).ListDeletedAsync(Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_RestoreHotkey_CallsRestoreApiAndReloads()
    {
        DeletedHotkeyDto deleted = new(Guid.NewGuid(), "Open Terminal", "T", true, false, false, false, DateTimeOffset.UtcNow);
        _hotstrings.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotstringDto[]>.Ok([]));
        _hotkeys.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(
                ApiResult<DeletedHotkeyDto[]>.Ok([deleted]),
                ApiResult<DeletedHotkeyDto[]>.Ok([]));
        _hotkeys.RestoreAsync(deleted.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(
                new HotkeyDto(
                    deleted.Id,
                    [],
                    true,
                    deleted.Description,
                    deleted.Key,
                    deleted.Ctrl,
                    deleted.Alt,
                    deleted.Shift,
                    deleted.Win,
                    HotkeyAction.Run,
                    "",
                    DateTimeOffset.UtcNow,
                    DateTimeOffset.UtcNow,
                    [])));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Open Terminal"));

        cut.Find("button.restore-item").Click();

        cut.WaitForAssertion(() =>
            _hotkeys.Received(1).RestoreAsync(deleted.Id, Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() =>
            _hotkeys.Received(2).ListDeletedAsync(Arg.Any<CancellationToken>()));
    }
}
