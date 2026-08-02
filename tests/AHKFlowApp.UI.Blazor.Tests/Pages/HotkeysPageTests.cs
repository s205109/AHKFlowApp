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

public sealed class HotkeysPageTests : BunitContext, IAsyncLifetime
{
    private static readonly HotkeyKeyDto[] CatalogKeys =
    [
        new("F1", "Function keys", ["HotkeyKey"], true),
        new("n", "Letters & digits", ["HotkeyKey"], false),
    ];

    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    private readonly IProfilesApiClient _profilesApi = Substitute.For<IProfilesApiClient>();
    private readonly ICategoriesApiClient _categoriesApi = Substitute.For<ICategoriesApiClient>();
    private readonly IHotkeyKeyCatalog _catalog = Substitute.For<IHotkeyKeyCatalog>();
    private readonly IKnownShortcutCatalog _knownShortcuts = Substitute.For<IKnownShortcutCatalog>();

    private IRenderedComponent<MudDialogProvider>? _dialogProvider;

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public HotkeysPageTests()
    {
        Services.AddSingleton(_api);

        IUserPreferencesService prefs = Substitute.For<IUserPreferencesService>();
        prefs.GetAsync(Arg.Any<CancellationToken>()).Returns(UserPreferences.Default);
        Services.AddSingleton(prefs);

        StubProfiles();
        Services.AddSingleton(_profilesApi);

        StubCategories();
        Services.AddSingleton(_categoriesApi);

        StubKeyCatalog(keysValid: true);
        Services.AddSingleton(_catalog);

        // The edit dialog and the list both inject this. The default is an empty catalog: most
        // page tests are about the grid and the dialog opening, not the notice.
        StubKnownShortcuts(new KnownShortcutCatalogDto([]));
        Services.AddSingleton(_knownShortcuts);

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<Hotkeys> RenderPage()
    {
        Render<MudPopoverProvider>();
        _dialogProvider = Render<MudDialogProvider>();
        return Render<Hotkeys>(p => p.AddCascadingValue(AuthenticatedState));
    }

    /// <summary>The dialog renders in its own root, so page assertions never see it.</summary>
    private IRenderedComponent<MudDialogProvider> DialogProvider =>
        _dialogProvider ?? throw new InvalidOperationException("Render the page first.");

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static HotkeyDto MakeHotkey(string description = "Open terminal", string key = "T") =>
        new(Guid.NewGuid(), [], true, description, key, true, false, false, false,
            HotkeyActionKind.Run, null, null, "wt.exe", RunTargetKind.Application, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    /// <summary>A Run row bound to Win+N — inline-editable, and its combo exercises the casing rule.</summary>
    private static HotkeyDto OneRunHotkey(string key = "n") =>
        new(Guid.NewGuid(), [], true, "Open notepad", key, false, false, false, true,
            HotkeyActionKind.Run, null, null, "notepad.exe", RunTargetKind.Application, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static HotkeyDto OneHotkeyOfKind(HotkeyActionKind kind)
    {
        HotkeyDto row = new(Guid.NewGuid(), [], true, "Kind row", "F1", false, false, false, true,
            kind, null, null, null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

        return kind switch
        {
            HotkeyActionKind.SendText => row with { Text = "hello" },
            HotkeyActionKind.SendKeys => row with { SendKeysContent = "^c" },
            HotkeyActionKind.Run => row with { RunTarget = "notepad.exe", RunTargetKind = RunTargetKind.Application },
            HotkeyActionKind.Window => row with { WindowOp = WindowOp.Minimize },
            HotkeyActionKind.Remap => row with { RemapDest = "F2" },
            HotkeyActionKind.Raw => row with { Body = "MsgBox \"hi\"" },
            _ => row,
        };
    }

    private IRenderedComponent<Hotkeys> RenderPageWith(HotkeyDto dto, bool keysValid = true)
    {
        StubKeyCatalog(keysValid);
        StubList(Page(dto));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        return cut;
    }

    private void StubKeyCatalog(bool keysValid)
    {
        _catalog.ForRoleAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult<IReadOnlyList<HotkeyKeyDto>>(
                [.. CatalogKeys.Where(k => k.Roles.Contains(call.Arg<string>()))]));
        _catalog.GroupOf(Arg.Any<string>())
            .Returns(call => CatalogKeys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.Group);
        _catalog.IsValidKey(Arg.Any<string>()).Returns(keysValid);
        _catalog.CanonicalizeAsync(Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string?>() ?? ""));
    }

    private void StubKnownShortcuts(KnownShortcutCatalogDto catalog) =>
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(catalog));

    /// <summary>The Windows use of Win+N, so a row bound to Win+N carries a marker.</summary>
    private static KnownShortcutCatalogDto WinNCatalog() =>
        new([
            new KnownShortcutDto("windows.notepad", "n", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open Notepad")],
                null),
        ]);

    private static ProfileDto MakeProfile(string name = "Work") =>
        new(Guid.NewGuid(), name, false, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static PagedList<HotkeyDto> Page(params HotkeyDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    private void StubList(PagedList<HotkeyDto> page) =>
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotkeyDto>>.Ok(page));

    private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotkeyDto>>.Failure(status, problem));

    private void StubProfiles(params ProfileDto[] profiles) =>
        _profilesApi.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    private void StubCategories(params CategoryDto[] categories)
    {
        PagedList<CategoryDto> page = new(categories, 1, 200, categories.Length, 1, false, false);
        _categoriesApi.ListAsync(Arg.Any<CategoryListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<CategoryDto>>.Ok(page));
    }

    /// <summary>Renders one inline-editable row and puts it into inline edit.</summary>
    private IRenderedComponent<Hotkeys> StartInlineEdit(HotkeyDto dto)
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(dto);

        cut.Find("button.start-edit").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]"));
        return cut;
    }

    // The key is a KeyPicker, not a plain text field: driving its ValueChanged is what a
    // selection from the dropdown does, without depending on popover/JS behaviour.
    private static Task SetKeyAsync(IRenderedComponent<Hotkeys> cut, string? key) =>
        cut.InvokeAsync(() => cut.FindComponent<KeyPicker>().Instance.ValueChanged.InvokeAsync(key));

    // Both branches render at once — the scoped CSS only hides one — so every marker assertion
    // is scoped to the branch it is about.
    private const string DesktopMarker = ".desktop-branch [data-test=\"known-shortcut-marker\"]";

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
    public void Page_HasSearchInput()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find(".search-hotkeys").Should().NotBeNull());
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
        cut.Find("button.bulk-delete-hotkeys").Click();

        cut.WaitForAssertion(() => _api.Received(1).BulkDeleteAsync(
            Arg.Is<IReadOnlyList<Guid>>(ids =>
                ids.Count == 2 &&
                ids.Contains(aId) &&
                ids.Contains(bId)),
            Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Any<HotkeyListRequest>(),
            Arg.Any<CancellationToken>()));
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
    public async Task Page_BlankKey_BlocksCommit_AndShowsValidationMessage()
    {
        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey("Open terminal", "T"));

        await SetKeyAsync(cut, "");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Key is required"));
        _ = _api.DidNotReceive().UpdateAsync(Arg.Any<Guid>(), Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public Task Page_BlankDescription_BlocksCommit_AndShowsValidationMessage()
    {
        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey("Open terminal", "T"));

        cut.Find("input[data-test=\"description-input\"]").Input("");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Description is required"));
        _api.DidNotReceive().UpdateAsync(Arg.Any<Guid>(), Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_EditExistingRow_CallsUpdate()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto with { Key = "F1" }));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        await SetKeyAsync(cut, "F1");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d => d.Key == "F1"), Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_EditRow_WithModifiers_CallsUpdate_AndKeepsActionChipVisible()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        // The kind is not inline-changeable, so the chip stays on as context for the one
        // payload field beside it — it replaces the old inline Action dropdown.
        cut.Find("[data-test=\"action-chip\"]").TextContent.Should().Contain("Run");
        cut.FindAll("[data-test=\"run-target-input\"]").Should().NotBeEmpty();

        // Ctrl starts on in the fixture, so clearing it is what proves the binding is two-way.
        cut.Find("input[data-test=\"ctrl-checkbox\"]").Change(false);
        cut.Find("input[data-test=\"shift-checkbox\"]").Change(true);
        cut.Find("input[data-test=\"win-checkbox\"]").Change(true);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.Description == "Open terminal" &&
                d.Key == "T" &&
                !d.Ctrl &&
                !d.Alt &&
                d.Shift &&
                d.Win),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_EditSendTextRow_CommitsTextAndNotRunTarget()
    {
        HotkeyDto dto = OneHotkeyOfKind(HotkeyActionKind.SendText);
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        // The other inline-editable kind: one field, bound to Text rather than RunTarget.
        cut.FindAll("[data-test=\"run-target-input\"]").Should().BeEmpty();
        cut.Find("input[data-test=\"text-input\"]").Input("Jane Smith");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.ActionKind == HotkeyActionKind.SendText &&
                d.Text == "Jane Smith" &&
                d.RunTarget == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Page_EditRow_WithSpecificProfiles_CallsUpdate()
    {
        ProfileDto work = MakeProfile("Work");
        ProfileDto personal = MakeProfile("Personal");
        StubProfiles(work, personal);
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull(), TimeSpan.FromSeconds(5));

        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id, personal.Id }));

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.AppliesToAllProfiles == false &&
                d.ProfileIds != null &&
                d.ProfileIds.Length == 2 &&
                d.ProfileIds.Contains(work.Id) &&
                d.ProfileIds.Contains(personal.Id)),
            Arg.Any<CancellationToken>()), TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Page_WhenAnyToggleIsReenabled_ClearsSpecificProfilesBeforeUpdate()
    {
        ProfileDto work = MakeProfile("Work");
        StubProfiles(work);
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull());
        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id }));

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(true);
        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"profile-select\"]").Should().BeEmpty());

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d =>
                d.AppliesToAllProfiles &&
                d.ProfileIds == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public Task Page_Delete_CancelPreventsDeleteAsync()
    {
        HotkeyDto dto = MakeHotkey();
        StubList(Page(dto));
        _api.DeleteAsync(dto.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        cut.Find("button.delete").Click();

        // ShowMessageBoxAsync renders via JS interop; confirm is not callable in bUnit.
        // JS is loose so the dialog resolves as null (cancel) — DeleteAsync NOT called.
        cut.WaitForAssertion(() => _api.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_OnConflictResponse_ApiCalledAndNoException()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(dto);
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d => d.Description == "Open terminal"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_CategoryEditorShowsMultiSelect_WhenEditing()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);

        IRenderedComponent<Hotkeys> cut = StartInlineEdit(MakeHotkey("Open terminal", "T"));

        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"category-select\"]").Should().NotBeEmpty());
    }

    [Fact]
    public async Task Page_ChipFilter_ReloadsDataWithCategoryIds()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Work"));

        await cut.InvokeAsync(() =>
            cut.FindComponent<MudChipSet<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id }));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(r =>
                r.CategoryIds != null &&
                r.CategoryIds.Contains(work.Id)),
            Arg.Any<CancellationToken>()));
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
    public async Task Page_ActionFilter_ReloadsDataWithSelectedAction()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> desktopActionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter\""));
        await cut.InvokeAsync(() => desktopActionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Remap));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(r => r.ActionKind == HotkeyActionKind.Remap),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Page_MobileActionFilter_ReloadsDataWithSelectedAction()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter-mobile\"]"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> mobileActionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter-mobile\""));
        await cut.InvokeAsync(() => mobileActionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Window));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotkeyListRequest>(r => r.ActionKind == HotkeyActionKind.Window),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_ActionFilter_ListsAllSevenKinds()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        // Desktop + mobile selects each render all HotkeyActionKind items - 7 kinds x 2 selects.
        IReadOnlyList<HotkeyActionKind?> allValues = [.. cut.FindComponents<MudSelectItem<HotkeyActionKind?>>()
            .Select(c => c.Instance.Value)];

        allValues.Should().HaveCount(14);
        allValues.Distinct().Should().BeEquivalentTo(
        [
            HotkeyActionKind.SendText, HotkeyActionKind.SendKeys, HotkeyActionKind.Run,
            HotkeyActionKind.Window, HotkeyActionKind.Remap, HotkeyActionKind.Disable,
            HotkeyActionKind.Raw,
        ]);
    }

    [Fact]
    public void Page_ActionColumn_FunnelFilterDisabled()
    {
        // The toolbar dropdown owns ActionKind. A live column funnel on the same field would be a
        // second control writing the same request value - keep it off (Hotstrings does the same
        // for its Kind column).
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<PropertyColumn<HotkeyEditModel, HotkeyActionKind>> actionColumn =
            cut.FindComponents<PropertyColumn<HotkeyEditModel, HotkeyActionKind>>().Single();

        actionColumn.Instance.Filterable.Should().BeFalse();
    }

    [Fact]
    public async Task Page_EmptyFilteredResults_ShowsClearFiltersButton()
    {
        // "You have no hotkeys" and "your filters matched nothing" need different copy, and only
        // the second can offer a way out.
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> actionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter\""));
        await cut.InvokeAsync(() => actionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Remap));

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("No hotkeys match these filters.");
            // Scoped to the grid: the mobile branch renders its own true-empty text until Task 3,
            // and this test is about the desktop empty state.
            cut.Find(".hotkeys-grid").InnerHtml.Should().NotContain("No hotkeys yet.");
            cut.FindAll(".hotkeys-grid button.clear-filters").Should().ContainSingle();
        });
    }

    [Fact]
    public async Task Page_ClearFilters_ResetsSearchActionAndCategoryAndReloads()
    {
        var categoryId = Guid.NewGuid();
        StubCategories(new CategoryDto(categoryId, "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"action-filter\"]"));

        IRenderedComponent<MudTextField<string>> search = cut
            .FindComponents<MudTextField<string>>()
            .First(c => c.Markup.Contains("search-hotkeys"));
        await cut.InvokeAsync(() => search.Instance.ValueChanged.InvokeAsync("term"));

        IRenderedComponent<MudSelect<HotkeyActionKind?>> actionFilter = cut
            .FindComponents<MudSelect<HotkeyActionKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"action-filter\""));
        await cut.InvokeAsync(() => actionFilter.Instance.ValueChanged.InvokeAsync(HotkeyActionKind.Remap));

        IRenderedComponent<CategoryFilterChips> chips = cut.FindComponents<CategoryFilterChips>().First();
        await cut.InvokeAsync(() => chips.Instance.SelectedIdsChanged.InvokeAsync([categoryId]));

        cut.WaitForAssertion(() => cut.Find(".hotkeys-grid button.clear-filters"));

        // The page's own first load was already an all-null request, so without this the assertion
        // below would pass even if Clear filters did nothing at all.
        _api.ClearReceivedCalls();

        await cut.InvokeAsync(() => cut.Find(".hotkeys-grid button.clear-filters").Click());

        cut.WaitForAssertion(() =>
        {
            _api.Received().ListAsync(
                Arg.Is<HotkeyListRequest>(r =>
                    r.Search == null
                    && r.ActionKind == null
                    && r.CategoryIds == null
                    && r.DescriptionFilter == null
                    && r.KeyFilter == null),
                Arg.Any<CancellationToken>());

            // The controls must visibly reset too - a cleared request with a still-filled search
            // box or dropdown is a half-done clear.
            search.Instance.GetState(x => x.Value).Should().BeNullOrEmpty();
            actionFilter.Instance.GetState(x => x.Value).Should().BeNull();
            chips.Instance.SelectedIds.Should().BeEmpty();
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
