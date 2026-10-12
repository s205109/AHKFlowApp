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
    private readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public RecycleBinPageTests()
    {
        Services.AddSingleton(_hotstrings);
        Services.AddSingleton(_hotkeys);
        Services.AddMudServices();
        // Registered after AddMudServices so this substitute wins over MudBlazor's own snackbar.
        Services.AddSingleton(_snackbar);
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

        // First column says whether the row is a Hotstring or a Hotkey. CONTEXT.md calls that
        // an Item; "Type" is on its Avoid list and clashed with a Hotstring's Kind.
        cut.Find("th").TextContent.Trim().Should().Be("Item");
    }

    [Fact]
    public void Page_OnEmptyBin_ShowsEmptyMessage()
    {
        StubDeleted([], []);

        IRenderedComponent<RecycleBin> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("No deleted items."));
    }

    [Fact]
    public void Page_OnLoad_StartsDeletedApiCallsInParallel()
    {
        TaskCompletionSource<ApiResult<DeletedHotstringDto[]>> hotstringsResult = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        _hotstrings.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(_ => hotstringsResult.Task);
        _hotkeys.ListDeletedAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<DeletedHotkeyDto[]>.Ok([]));

        IRenderedComponent<RecycleBin> cut = RenderPage();

        // The hotkeys call is the signal. It happens while the hotstrings call is still pending,
        // which a page that awaited the two in turn could never reach.
        cut.WaitForAssertion(() => _hotkeys.Received(1).ListDeletedAsync(Arg.Any<CancellationToken>()));

        hotstringsResult.SetResult(ApiResult<DeletedHotstringDto[]>.Ok([]));

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
                    HotkeyActionKind.Run,
                    null,
                    null,
                    "notepad.exe",
                    RunTargetKind.Application,
                    null,
                    null,
                    null,
                    null,
                    null,
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

    [Fact]
    public void Restore_WhenResponseCarriesWarnings_ShowsWarningSnackbarNamingTheRule()
    {
        DeletedHotstringDto deleted = new(
            Guid.NewGuid(), "bad1", "text", null, DateTimeOffset.UtcNow);
        StubDeleted([deleted], []);

        // A Restore that succeeded but came back applying to no profile.
        HotstringDto restored = new(
            Id: deleted.Id,
            ProfileIds: [],
            AppliesToAllProfiles: false,
            Trigger: "bad1",
            Replacement: "text",
            Description: null,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false,
            CreatedAt: DateTimeOffset.UtcNow,
            UpdatedAt: DateTimeOffset.UtcNow,
            CategoryIds: [],
            RestoreWarnings: ["ContextValue must not contain double-quote characters."]);
        _hotstrings.RestoreAsync(deleted.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(restored));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.restore-item"));
        cut.Find("button.restore-item").Click();

        cut.WaitForAssertion(() => _snackbar.Received(1).Add(
            Arg.Is<string>(m => m.Contains("applies to no profile")
                             && m.Contains("ContextValue must not contain double-quote characters.")),
            Severity.Warning,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));

        _snackbar.DidNotReceive().Add(
            "Hotstring restored.", Severity.Success,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());
    }

    // The warning is the only place an Owner ever sees why the item came back inert: nothing
    // persisted records it, so a toast that dismisses itself after five seconds loses the one
    // copy. It stays up until they close it.
    [Fact]
    public void Restore_WhenResponseCarriesWarnings_KeepsTheWarningUpUntilDismissed()
    {
        DeletedHotstringDto deleted = new(
            Guid.NewGuid(), "bad2", "text", null, DateTimeOffset.UtcNow);
        StubDeleted([deleted], []);
        _hotstrings.RestoreAsync(deleted.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(RestoredWithWarnings(deleted.Id, "bad2")));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.restore-item"));
        cut.Find("button.restore-item").Click();

        cut.WaitForAssertion(() => _snackbar.Received(1).Add(
            Arg.Any<string>(), Severity.Warning,
            Arg.Is<Action<SnackbarOptions>>(configure => RequiresInteraction(configure)),
            Arg.Any<string>()));
    }

    // Two failed rules in one message. Every rule message already ends in a period, so joining
    // them with "; " would read "...whitespace.; ContextValue...".
    [Fact]
    public void Restore_WithTwoWarnings_JoinsThemWithoutAStraySemicolon()
    {
        DeletedHotstringDto deleted = new(
            Guid.NewGuid(), "bad3", "text", null, DateTimeOffset.UtcNow);
        StubDeleted([deleted], []);
        _hotstrings.RestoreAsync(deleted.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(RestoredWithWarnings(
                deleted.Id,
                "bad3",
                "Trigger must not have leading or trailing whitespace.",
                "ContextValue must not contain double-quote characters.")));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.restore-item"));
        cut.Find("button.restore-item").Click();

        cut.WaitForAssertion(() => _snackbar.Received(1).Add(
            Arg.Is<string>(m => m.Contains("whitespace. ContextValue") && !m.Contains(".;")),
            Severity.Warning,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));
    }

    // The hotkey half of the same page code. Without this, returning null from
    // RestoreHotkeyAsync's warnings expression breaks nothing.
    [Fact]
    public void RestoreHotkey_WhenResponseCarriesWarnings_ShowsWarningSnackbarNamingTheRule()
    {
        DeletedHotkeyDto deleted = new(
            Guid.NewGuid(), "Open Notepad", "N", true, false, false, false, DateTimeOffset.UtcNow);
        StubDeleted([], [deleted]);

        HotkeyDto restored = new(
            deleted.Id,
            [],
            false,
            deleted.Description,
            "NotAKeyName",
            deleted.Ctrl,
            deleted.Alt,
            deleted.Shift,
            deleted.Win,
            HotkeyActionKind.Run,
            null,
            null,
            "notepad.exe",
            RunTargetKind.Application,
            null,
            null,
            null,
            null,
            null,
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow,
            [],
            ["Key must be a known key name (for example a, F5, Escape, Numpad0)."]);
        _hotkeys.RestoreAsync(deleted.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(restored));

        IRenderedComponent<RecycleBin> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.restore-item"));
        cut.Find("button.restore-item").Click();

        cut.WaitForAssertion(() => _snackbar.Received(1).Add(
            Arg.Is<string>(m => m.Contains("Hotkey restored, but it applies to no profile")
                             && m.Contains("Key must be a known key name")),
            Severity.Warning,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));

        _snackbar.DidNotReceive().Add(
            "Hotkey restored.", Severity.Success,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());
    }

    private static HotstringDto RestoredWithWarnings(Guid id, string trigger, params string[] warnings) =>
        new(
            Id: id,
            ProfileIds: [],
            AppliesToAllProfiles: false,
            Trigger: trigger,
            Replacement: "text",
            Description: null,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false,
            CreatedAt: DateTimeOffset.UtcNow,
            UpdatedAt: DateTimeOffset.UtcNow,
            CategoryIds: [],
            RestoreWarnings: warnings.Length > 0
                ? warnings
                : ["ContextValue must not contain double-quote characters."]);

    // Runs the page's own options callback and reports what it set, so the assertion reads the
    // real configuration rather than trusting that a callback was passed at all.
    private static bool RequiresInteraction(Action<SnackbarOptions>? configure)
    {
        if (configure is null)
            return false;

        SnackbarOptions options = new(Severity.Warning, new SnackbarConfiguration());
        configure(options);
        return options.RequireInteraction == true;
    }
}
