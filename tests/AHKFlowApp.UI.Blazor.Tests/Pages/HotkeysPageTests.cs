using System.Security.Claims;
using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HotkeysPageTests : HotkeysPageTestsBase
{
    // Backlog 210: the hotkey grid showed an empty Profiles cell for an item with no profile.
    [Fact]
    public void Grid_ItemWithNoProfile_ShowsOneNoProfileChip()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(MakeHotkey() with { AppliesToAllProfiles = false });
        // MakeHotkey has no categories, so exactly one chip also proves the Categories cell stays empty.
        cut.FindAll(".no-profile-chip").Should().ContainSingle().Which.TextContent.Should().Contain("No profile");
    }

    [Fact]
    public void Mobile_RowMatchingAKnownShortcut_ShowsTheMarker()
    {
        StubKnownShortcuts(WinNCatalog());

        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.WaitForAssertion(() => cut.FindAll(MobileMarker).Should().ContainSingle());
    }

    [Fact]
    public void Grid_RowMatchingAKnownShortcut_ShowsTheMarker()
    {
        StubKnownShortcuts(WinNCatalog());

        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.WaitForAssertion(() => cut.FindAll(DesktopMarker).Should().ContainSingle());

        IElement marker = cut.Find(DesktopMarker);
        marker.GetAttribute("role").Should().Be("img");
        marker.GetAttribute("tabindex").Should().Be("0");
        marker.GetAttribute("aria-label").Should().Be(
            "Windows uses Win+N to open Notepad. Your hotkey may override this shortcut.");
    }

    [Fact]
    public void Grid_RowMatchingNothing_ShowsNoMarker()
    {
        StubKnownShortcuts(WinNCatalog());

        // F1 with Win held is not the Win+N row, so nothing marks it.
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneHotkeyOfKind(HotkeyActionKind.Run));

        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.FindAll(DesktopMarker).Should().BeEmpty();
    }

    [Fact]
    public async Task Grid_RowInInlineEdit_ShowsNoMarker()
    {
        StubKnownShortcuts(WinNCatalog());

        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());
        cut.WaitForAssertion(() => cut.FindAll(DesktopMarker).Should().ContainSingle());

        // The inline row renders the full ShortcutWarning alert, so an icon would say the same
        // thing twice.
        await cut.InvokeAsync(() => cut.Find(".desktop-branch button.start-edit").Click());

        cut.WaitForAssertion(() => cut.FindAll(DesktopMarker).Should().BeEmpty());
    }

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        StubList(Page(dto));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Open terminal"));

        cut.Markup.Should().Contain("Open terminal");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        StubListFailure(ApiResultStatus.NetworkError);

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }

    [Fact]
    public void Page_AddButton_OpensCreateDialog()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));

        cut.Find("button.add-hotkey").Click();

        // A new hotkey has to pick an action kind, which the grid cannot express, so Add opens
        // the dialog instead of an inline draft row.
        DialogProvider.WaitForAssertion(() =>
            DialogProvider.Markup.Should().Contain("New hotkey"));
        cut.FindAll("input[data-test=\"description-input\"]").Should().BeEmpty();
    }

    [Fact]
    public void Page_OnLoad_UsesGridListRequest()
    {
        StubList(Page());

        RenderPage();

        _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(request =>
                request.Page == 1 &&
                request.PageSize == UserPreferences.Default.RowsPerPage),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public void Page_HasReloadButton()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find("button.reload-hotkeys").Should().NotBeNull());
    }

    [Fact]
    public void Page_NoSelection_HidesBulkDeleteButton()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));

        cut.FindAll("button.bulk-delete-hotkeys").Should().BeEmpty();
    }

    [Fact]
    public async Task Page_BulkDelete_CallsApiAndReloads()
    {
        var aId = Guid.NewGuid();
        var bId = Guid.NewGuid();
        HotkeyDto a = MakeHotkey("desc-a", "F1") with { Id = aId };
        HotkeyDto b = MakeHotkey("desc-b", "F2") with { Id = bId };
        StubList(Page(a, b));
        _api.BulkDeleteAsync(Arg.Any<IReadOnlyList<Guid>>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<BulkDeleteResultDto>.Ok(new BulkDeleteResultDto(2, [])));

        IDialogService dialogService = Substitute.For<IDialogService>();
        dialogService.ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>())
            .Returns(Task.FromResult<bool?>(true));
        Services.AddSingleton(dialogService);

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("desc-a"));

        await cut.InvokeAsync(() => cut.Instance.OnSelectedItemsChanged(
            [HotkeyEditModel.FromDto(a), HotkeyEditModel.FromDto(b)]));

        cut.WaitForAssertion(() => cut.Find("button.bulk-delete-hotkeys"));

        // An empty page is what the next load returns once both rows are gone.
        StubList(Page());

        cut.Find("button.bulk-delete-hotkeys").Click();

        cut.WaitForAssertion(() => _api.Received(1).BulkDeleteAsync(
            Arg.Is<IReadOnlyList<Guid>>(ids =>
                ids.Count == 2 &&
                ids.Contains(aId) &&
                ids.Contains(bId)),
            Arg.Any<CancellationToken>()));

        // Scoped to the branch: the desktop grid and the mobile list both render, and only the
        // mobile one is at risk here. Naming rows that must be gone cannot pass from the initial
        // load, unlike a bare Received() on ListAsync.
        cut.WaitForAssertion(() =>
        {
            string mobile = cut.Find(".mobile-branch").TextContent;
            mobile.Should().NotContain("desc-a");
            mobile.Should().NotContain("desc-b");
        });
    }

    // Backlog 169: a bulk delete of one row read "Delete 1 hotkey(s)? You can restore them".
    // No test read the delete text, so nothing caught it.
    [Fact]
    public async Task Page_BulkDeleteOfOneRow_ReadsAsSingular()
    {
        HotkeyDto a = MakeHotkey("desc-a", "F1") with { Id = Guid.NewGuid() };
        StubList(Page(a));
        _api.BulkDeleteAsync(Arg.Any<IReadOnlyList<Guid>>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<BulkDeleteResultDto>.Ok(new BulkDeleteResultDto(1, [])));

        IDialogService dialogService = Substitute.For<IDialogService>();
        dialogService.ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>())
            .Returns(Task.FromResult<bool?>(true));
        Services.AddSingleton(dialogService);
        // Registered after the constructor's AddMudServices, so it wins over MudBlazor's snackbar.
        ISnackbar snackbar = Substitute.For<ISnackbar>();
        Services.AddSingleton(snackbar);

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("desc-a"));

        await cut.InvokeAsync(() => cut.Instance.OnSelectedItemsChanged([HotkeyEditModel.FromDto(a)]));

        cut.WaitForAssertion(() => cut.Find("button.bulk-delete-hotkeys"));
        cut.Find("button.bulk-delete-hotkeys").Click();

        cut.WaitForAssertion(() => dialogService.Received(1).ShowMessageBoxAsync(
            Arg.Is<string>(t => t == "Delete hotkey?"),
            Arg.Is<string>(m => m == "Delete 1 hotkey? You can restore it from the Recycle Bin."),
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<DialogOptions>()));
        cut.WaitForAssertion(() => snackbar.Received(1).Add(
            "Deleted 1 hotkey.", Severity.Success,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));
    }

    [Fact]
    public void Page_ReloadWhileExpanded_KeepsMobileRowControls()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(
                ApiResult<PagedList<HotkeyDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotkeyDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotkeyDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotkeyDto>>.Ok(Page(dto)));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find(".mobile-row"));
        cut.Find(".mobile-row").Click();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));

        cut.Find("button.reload-hotkeys-mobile").Click();

        cut.WaitForAssertion(() => _api.Received(2).ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() =>
        {
            cut.Find("button.start-edit").Should().NotBeNull();
            cut.Markup.Should().Contain("Open terminal");
        });
    }

    [Fact]
    public Task Page_Delete_CancelPreventsDeleteAsync()
    {
        HotkeyDto dto = MakeHotkey();
        StubList(Page(dto));
        _api.DeleteAsync(dto.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        // The stub answers the confirmation with "cancel". Without it the message box stays open
        // and the delete handler stays suspended, so the test would prove nothing.
        IDialogService dialogService = Substitute.For<IDialogService>();
        dialogService.ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>())
            .Returns(Task.FromResult<bool?>(false));
        Services.AddSingleton(dialogService);

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        cut.Find("button.delete").Click();

        // The answered confirmation is the signal that the cancel path ran.
        cut.WaitForAssertion(() => dialogService.Received(1).ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>()));

        _ = _api.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public void Grid_RendersSixColumnsPlusSelectAndActions()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        IReadOnlyList<string> headers = [.. cut.FindAll("th").Select(th => th.TextContent.Trim())];

        headers.Should().Contain(["Description", "Hotkey", "Action", "Profiles", "Categories"]);
        headers.Should().NotContain(["Ctrl", "Alt", "Shift", "Win", "Key", "Parameters"]);
    }

    // The mobile branch renders from the same stub in the same tree, so both of these scope to
    // .desktop-branch — an unscoped Markup assertion would pass on the mobile list alone.
    [Fact]
    public void Grid_ActionCellShowsChipAndSummary()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.Find(".desktop-branch [data-test=\"action-chip\"]").TextContent.Should().Contain("Run");
        cut.Find(".desktop-branch td:nth-child(4)").TextContent.Should().Contain("notepad.exe");
    }

    [Fact]
    public void Grid_HotkeyCellShowsComboLabel()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.Find(".desktop-branch td code").TextContent.Should().Be("Win+N");
    }

    [Fact]
    public void EditButton_OnRawRow_OpensDialogInsteadOfInlineEdit()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneHotkeyOfKind(HotkeyActionKind.Raw));

        cut.Find(".start-edit").Click();

        // The dialog renders in the provider's own root, never in the page's.
        DialogProvider.WaitForAssertion(() =>
            DialogProvider.FindAll("[data-test=\"raw-body-input\"]").Should().NotBeEmpty());
        cut.FindAll(".commit-edit").Should().BeEmpty();
    }

    [Fact]
    public void EditButton_OnRunRow_StartsInlineEdit()
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey());

        cut.Find(".start-edit").Click();

        cut.WaitForAssertion(() => cut.FindAll(".commit-edit").Should().ContainSingle());
    }

    [Fact]
    public void EditButton_OnRunRowWithLegacyInvalidKey_OpensDialog()
    {
        // Catalog reports the key invalid -> the row is not inline-editable even though its
        // kind is Run, which is how un-migratable legacy rows surface with no extra UI.
        IRenderedComponent<Hotkeys> cut = RenderPageWith(OneRunHotkey(key: "!!legacy!!"), keysValid: false);

        cut.Find(".start-edit").Click();

        DialogProvider.WaitForAssertion(() =>
            DialogProvider.FindAll("input[data-test=\"key-picker\"]").Should().NotBeEmpty());
        cut.FindAll(".commit-edit").Should().BeEmpty();
    }

    [Fact]
    public void Page_RendersCssGatedDesktopAndMobileBranches()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Find(".desktop-branch button.add-hotkey").Should().NotBeNull();
            cut.Find(".mobile-branch button.add-hotkey-fab").Should().NotBeNull();
            cut.Find(".mobile-branch button.add-hotkey-fab").GetAttribute("aria-label").Should().Be("Add hotkey");
        });
    }

    [Fact]
    public void Grid_HotkeyLimitedToOneWindow_ShowsTheContextIcon()
    {
        StubKeyCatalog(keysValid: true);
        StubList(Page(MakeHotkey() with
        {
            ContextMatchType = WindowMatchType.Executable,
            ContextValue = "notepad.exe",
        }));

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() => cut.FindAll(".context-icon").Should().ContainSingle());
    }

    [Fact]
    public void Grid_GlobalHotkey_ShowsNoContextIcon()
    {
        StubKeyCatalog(keysValid: true);
        StubList(Page(MakeHotkey()));

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.FindAll(".context-icon").Should().BeEmpty();
    }
}
