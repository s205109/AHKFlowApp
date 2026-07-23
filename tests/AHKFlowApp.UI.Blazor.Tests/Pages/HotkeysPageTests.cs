using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HotkeysPageTests : BunitContext, IAsyncLifetime
{
    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    private readonly IProfilesApiClient _profilesApi = Substitute.For<IProfilesApiClient>();
    private readonly ICategoriesApiClient _categoriesApi = Substitute.For<ICategoriesApiClient>();

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

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<Hotkeys> RenderPage()
    {
        Render<MudPopoverProvider>();
        Render<MudDialogProvider>();
        return Render<Hotkeys>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static HotkeyDto MakeHotkey(string description = "Open terminal", string key = "T") =>
        new(Guid.NewGuid(), [], true, description, key, true, false, false, false,
            HotkeyActionKind.Run, null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            Action: HotkeyAction.Run, Parameters: "");

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

    private static void StartDraftEdit(IRenderedComponent<Hotkeys> cut)
    {
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));
        cut.Find("button.add-hotkey").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]"));
    }

    private static void FillRequiredFields(IRenderedComponent<Hotkeys> cut, string description = "Open terminal", string key = "T")
    {
        cut.Find("input[data-test=\"description-input\"]").Input(description);
        cut.Find("input[data-test=\"key-input\"]").Input(key);
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
    public void Page_AddButton_StartsDraftGridEdit()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));

        cut.Find("button.add-hotkey").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]").Should().NotBeNull());
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
    public Task Page_SaveDraftRow_CallsCreate()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(MakeHotkey("Open terminal", "T")));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.Description == "Open terminal" && d.Key == "T"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_BlankKey_BlocksCommit_AndShowsValidationMessage()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        StartDraftEdit(cut);
        cut.Find("input[data-test=\"description-input\"]").Input("Open terminal");
        // Leave key empty
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Key is required"));
        _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_BlankDescription_BlocksCommit_AndShowsValidationMessage()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();
        StartDraftEdit(cut);
        cut.Find("input[data-test=\"key-input\"]").Input("T");
        // Leave description empty
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Description is required"));
        _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EditExistingRow_CallsUpdate()
    {
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(dto with { Key = "F1" }));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();
        cut.Find("input[data-test=\"key-input\"]").Input("F1");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotkeyDto>(d => d.Key == "F1"), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_SaveDraftRow_WithModifiersAndActionSelection_CallsCreate()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(MakeHotkey("Open terminal", "T")));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);

        cut.Find("input[data-test=\"ctrl-checkbox\"]").Change(true);
        cut.Find("input[data-test=\"shift-checkbox\"]").Change(true);
        cut.Find("input[data-test=\"win-checkbox\"]").Change(true);

        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<HotkeyAction>>().Instance.ValueChanged.InvokeAsync(HotkeyAction.Run));

        cut.Find("button.commit-edit").Click();

        // The legacy Action dropdown still renders (retired in Task 9/10) and still updates
        // HotkeyEditModel.Action, but HotkeyEditModel no longer forwards that legacy field onto
        // the wire (see HotkeyEditModel.ToCreateDto) — ActionKind/per-kind fields are the
        // contract now, so this assertion no longer checks d.Action.
        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d =>
                d.Description == "Open terminal" &&
                d.Key == "T" &&
                d.Ctrl &&
                !d.Alt &&
                d.Shift &&
                d.Win),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task Page_SaveDraftRow_WithSpecificProfiles_CallsCreate()
    {
        ProfileDto work = MakeProfile("Work");
        ProfileDto personal = MakeProfile("Personal");
        StubProfiles(work, personal);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(MakeHotkey("Open terminal", "T")));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull(), TimeSpan.FromSeconds(5));

        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id, personal.Id }));

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d =>
                d.AppliesToAllProfiles == false &&
                d.ProfileIds != null &&
                d.ProfileIds.Length == 2 &&
                d.ProfileIds.Contains(work.Id) &&
                d.ProfileIds.Contains(personal.Id)),
            Arg.Any<CancellationToken>()), TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task Page_WhenAnyToggleIsReenabled_ClearsSpecificProfilesBeforeCreate()
    {
        ProfileDto work = MakeProfile("Work");
        StubProfiles(work);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(MakeHotkey("Open terminal", "T")));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(false);
        cut.WaitForAssertion(() => cut.FindComponent<MudSelect<Guid>>().Should().NotBeNull());
        await cut.InvokeAsync(() =>
            cut.FindComponent<MudSelect<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id }));

        cut.Find("input[data-test=\"applies-to-all-checkbox\"]").Change(true);
        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"profile-select\"]").Should().BeEmpty());

        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d =>
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
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));
        cut.Find("button.add-hotkey").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]"));
        cut.Find("input[data-test=\"description-input\"]").Input("Open terminal");
        cut.Find("input[data-test=\"key-input\"]").Input("T");
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.Description == "Open terminal"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_CategoryEditorShowsMultiSelect_WhenEditing()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);
        HotkeyDto dto = MakeHotkey("Open terminal", "T");
        StubList(Page(dto));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();

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
    public void Page_RendersCssGatedDesktopAndMobileBranches()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Find(".desktop-branch button.add-hotkey").Should().NotBeNull();
            cut.Find(".mobile-branch button.add-hotkey-fab").Should().NotBeNull();
        });
    }
}
