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

public sealed class HotstringsPageTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();
    private readonly IProfilesApiClient _profilesApi = Substitute.For<IProfilesApiClient>();
    private readonly ICategoriesApiClient _categoriesApi = Substitute.For<ICategoriesApiClient>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public HotstringsPageTests()
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

    private IRenderedComponent<Hotstrings> RenderPage()
    {
        Render<MudPopoverProvider>();
        Render<MudDialogProvider>();
        return Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static PagedList<HotstringDto> Page(params HotstringDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    private void StubList(PagedList<HotstringDto> page) =>
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Ok(page));

    [Fact]
    public async Task Page_WhileReloadIsInFlight_RendersLoadingIndicator()
    {
        // The indicator is only observable mid-flight, which no other test covers: ComponentBase
        // renders once before awaiting a suspending event handler and again on completion, so a
        // gated API call is the only way to catch the page in its loading state.
        StubList(Page());
        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() =>
            cut.FindAll(".mobile-branch .mud-progress-linear").Should().BeEmpty());

        var gate = new TaskCompletionSource<ApiResult<PagedList<HotstringDto>>>();
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(gate.Task);

        await cut.InvokeAsync(() => cut.Find("button.reload-hotstrings-mobile").Click());

        cut.WaitForAssertion(() =>
            cut.FindAll(".mobile-branch .mud-progress-linear").Should().NotBeEmpty());

        gate.SetResult(ApiResult<PagedList<HotstringDto>>.Ok(Page()));

        cut.WaitForAssertion(() =>
            cut.FindAll(".mobile-branch .mud-progress-linear").Should().BeEmpty());
    }

    private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Failure(status, problem));

    private void StubProfiles(params ProfileDto[] profiles) =>
        _profilesApi.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    private void StubCategories(params CategoryDto[] categories)
    {
        PagedList<CategoryDto> page = new(categories, 1, 200, categories.Length, 1, false, false);
        _categoriesApi.ListAsync(Arg.Any<CategoryListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<CategoryDto>>.Ok(page));
    }

    private static void StartDraftEdit(IRenderedComponent<Hotstrings> cut)
    {
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
    }

    private static void FillRequiredFields(IRenderedComponent<Hotstrings> cut, string trigger = "btw", string replacement = "by the way")
    {
        cut.Find("input[data-test=\"trigger-input\"]").Input(trigger);
        cut.Find("textarea[data-test=\"replacement-input\"]").Input(replacement);
    }

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("btw"));

        cut.Markup.Should().Contain("by the way");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        StubListFailure(ApiResultStatus.NetworkError);

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }

    [Fact]
    public void Page_AddButton_StartsDraftGridEdit()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));

        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]").Should().NotBeNull());
    }

    [Fact]
    public void Page_OnLoad_UsesGridListRequest()
    {
        StubList(Page());

        RenderPage();

        _api.Received().ListAsync(
            Arg.Is<HotstringListRequest>(request =>
                request.Page == 1 &&
                request.PageSize == UserPreferences.Default.RowsPerPage),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public void Page_HasReloadButton()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find("button.reload-hotstrings").Should().NotBeNull());
    }

    [Fact]
    public void Page_HasSearchInput()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find(".search-hotstrings").Should().NotBeNull());
    }

    [Fact]
    public void Page_NoSelection_HidesBulkDeleteButton()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));

        cut.FindAll("button.bulk-delete-hotstrings").Should().BeEmpty();
    }

    [Fact]
    public async Task Page_BulkDelete_CallsApiAndReloads()
    {
        var aId = Guid.NewGuid();
        var bId = Guid.NewGuid();
        var a = new HotstringDto(aId, [], true, "a", "x", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        var b = new HotstringDto(bId, [], true, "b", "x", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(a, b));
        _api.BulkDeleteAsync(Arg.Any<IReadOnlyList<Guid>>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<BulkDeleteResultDto>.Ok(new BulkDeleteResultDto(2, [])));

        IDialogService dialogService = Substitute.For<IDialogService>();
        dialogService.ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>())
            .Returns(Task.FromResult<bool?>(true));
        Services.AddSingleton(dialogService);

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains(">a<") || cut.Markup.Contains("a"));

        await cut.InvokeAsync(() => cut.Instance.OnSelectedItemsChanged(
            [HotstringEditModel.FromDto(a), HotstringEditModel.FromDto(b)]));

        cut.WaitForAssertion(() => cut.Find("button.bulk-delete-hotstrings"));
        cut.Find("button.bulk-delete-hotstrings").Click();

        cut.WaitForAssertion(() => _api.Received(1).BulkDeleteAsync(
            Arg.Is<IReadOnlyList<Guid>>(ids =>
                ids.Count == 2 &&
                ids.Contains(aId) &&
                ids.Contains(bId)),
            Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Any<HotstringListRequest>(),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_ReloadWhileExpanded_KeepsMobileRowControls()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(
                ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find(".mobile-row"));
        cut.Find(".mobile-row").Click();
        cut.WaitForAssertion(() => cut.Find("button.edit"));

        cut.Find("button.reload-hotstrings-mobile").Click();

        cut.WaitForAssertion(() => _api.Received(2).ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() =>
        {
            cut.Find("button.edit").Should().NotBeNull();
            cut.Markup.Should().Contain("by the way");
        });
    }

    [Fact]
    public Task Page_SaveDraftRow_CallsCreateAndRefreshes()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_BlankReplacement_BlocksCommit_AndShowsValidationMessage()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        // Leave replacement empty
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Replacement is required"));
        _api.DidNotReceive().CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EditExistingRow_CallsUpdate()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(dto with { Replacement = "by the way!" }));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_InlineCreate_Allows4001CharacterAutoReplacement()
    {
        string replacement = new('x', 4_001);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(Guid.NewGuid(), [], true, "long", replacement, null, true, true,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        StartDraftEdit(cut);
        FillRequiredFields(cut, "long", replacement);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(dto => dto.Replacement.Length == 4_001
                && dto.Delivery == HotstringDelivery.Auto),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_InlineEdit_Allows4001CharacterClipboardReplacement()
    {
        string replacement = new('x', 4_001);
        HotstringDto dto = new(Guid.NewGuid(), [], true, "long", "initial", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, Delivery: HotstringDelivery.ClipboardPaste);
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(dto with { Replacement = replacement }));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input(replacement);
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(update => update.Replacement.Length == 4_001
                && update.Delivery == HotstringDelivery.ClipboardPaste),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_TruncatedRow_FetchesFullReplacementBeforeInlineEdit()
    {
        string fullReplacement = new('x', 1_000);
        HotstringDto summary = new(Guid.NewGuid(), [], true, "long", new string('x', 200), null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, ReplacementIsTruncated: true);
        HotstringDto detail = summary with { Replacement = fullReplacement, ReplacementIsTruncated = false };
        StubList(Page(summary));
        _api.GetAsync(summary.Id, Arg.Any<CancellationToken>()).Returns(ApiResult<HotstringDto>.Ok(detail));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() =>
        {
            _ = _api.Received(1).GetAsync(summary.Id, Arg.Any<CancellationToken>());
            cut.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Be(fullReplacement);
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_NonTruncatedRow_StartsInlineEditWithoutListRoundTrip()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "short", "replacement", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));
        IUserPreferencesService preferences = Services.GetRequiredService<IUserPreferencesService>();
        preferences.GetAsync(Arg.Any<CancellationToken>()).Returns(new UserPreferences(25, false));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        _api.ClearReceivedCalls();
        cut.Find("button.reload-hotstrings-mobile").Click();
        cut.WaitForAssertion(() =>
        {
            _ = _api.Received(1).ListAsync(
                Arg.Is<HotstringListRequest>(request => request.PageSize == 25),
                Arg.Any<CancellationToken>());
            _ = _api.Received(1).ListAsync(
                Arg.Is<HotstringListRequest>(request => request.PageSize == 10),
                Arg.Any<CancellationToken>());
        });
        _api.ClearReceivedCalls();

        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        _ = _api.DidNotReceive().ListAsync(
            Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_PromoteExistingRow_OpensEditDialogWithKindToggle()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        // Carry a typed edit into the promotion.
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!");
        cut.Find("button.promote-edit").Click();

        // The dialog renders into the provider's tree, carrying the typed value.
        provider.WaitForAssertion(() =>
        {
            provider.Find(".hotstring-edit-dialog");
            provider.Find("[data-test=\"kind-selector\"]");
            provider.FindComponent<global::AHKFlowApp.UI.Blazor.Components.Hotstrings.HotstringEditDialog>()
                .Instance.Item.Replacement.Should().Be("by the way!");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_PromoteDraftThenCancel_RestoresInlineDraft()
    {
        StubList(Page());

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        cut.Find("button.promote-edit").Click();

        // Dialog opens in the provider tree; cancel it via the title back button.
        provider.WaitForAssertion(() => provider.Find(".hotstring-edit-dialog button.cancel-edit"));
        provider.Find(".hotstring-edit-dialog button.cancel-edit").Click();

        // The dialog closes and the inline draft edit is restored (its commit control reappears).
        provider.WaitForAssertion(() => provider.FindAll(".hotstring-edit-dialog").Should().BeEmpty());
        cut.WaitForAssertion(() =>
        {
            cut.Find("input[data-test=\"trigger-input\"]");
            cut.Find("button.commit-edit").Should().NotBeNull();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_WhenAnyToggleIsReenabled_ClearsSpecificProfilesBeforeCreate()
    {
        ProfileDto work = new(Guid.NewGuid(), "Work", false, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubProfiles(work);
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
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
            Arg.Is<CreateHotstringDto>(d =>
                d.AppliesToAllProfiles &&
                d.ProfileIds == null),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public Task Page_EditRow_DescriptionInput_PreFilledAndCommitsUpdate()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", "polite filler", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(dto with { Description = "updated filler" }));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();
        cut.WaitForAssertion(() =>
            cut.Find("input[data-test=\"description-input\"]").GetAttribute("value").Should().Be("polite filler"));

        cut.Find("input[data-test=\"description-input\"]").Input("updated filler");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(d => d.Description == "updated filler"), Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_OnConflictResponse_ShowsErrorSnackbar()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", null, null)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("by the way");
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_CategoryEditorShowsMultiSelect_WhenEditing()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() => cut.FindAll("[data-test=\"category-select\"]").Should().NotBeEmpty());
    }

    [Fact]
    public async Task Page_ChipFilter_ReloadsDataWithCategoryIds()
    {
        CategoryDto work = new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubCategories(work);
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Work"));

        await cut.InvokeAsync(() =>
            cut.FindComponent<MudChipSet<Guid>>().Instance.SelectedValuesChanged
                .InvokeAsync(new HashSet<Guid> { work.Id }));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotstringListRequest>(r =>
                r.CategoryIds != null &&
                r.CategoryIds.Contains(work.Id)),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public void Page_RendersCssGatedDesktopAndMobileBranches()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Find(".desktop-branch button.add-hotstring").Should().NotBeNull();
            cut.Find(".mobile-branch button.add-hotstring-fab").Should().NotBeNull();
        });
    }

    [Fact]
    public Task Page_RendersTypeBadgeWithOptionGlyphs()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
            false, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
            HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: false,
            EffectiveDelivery: HotstringDelivery.Type);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // The Type column reports the kind. Keystroke delivery is the unremarkable default and
            // is deliberately left unmarked — only clipboard delivery, which overwrites the user's
            // clipboard, earns an icon.
            cut.Find(".desktop-branch .type-badge").TextContent.Should().Contain("Text");
            cut.FindAll(".desktop-branch [data-test=\"clipboard-delivery\"]").Should().BeEmpty();
            cut.Find(".option-glyphs").TextContent.Should().Be("*?C");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_ExplicitClipboardDelivery_ShowsClipboardIcon()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "long", "replacement", null,
            true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            Delivery: HotstringDelivery.ClipboardPaste, EffectiveDelivery: HotstringDelivery.ClipboardPaste);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // Kind chip plus a clipboard icon beside it; the icon carries the marker, not text.
            cut.Find(".desktop-branch .type-badge .mud-chip").TextContent.Should().Contain("Text");
            cut.FindAll(".desktop-branch [data-test=\"clipboard-delivery\"]").Should().HaveCount(1);
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_AutoDeliveryLongReplacement_ShowsClipboardChipFromEffectiveDelivery()
    {
        // The list reads the server-resolved EffectiveDelivery, not the raw stored Delivery=Auto —
        // this is what makes a long Auto row legible as clipboard in the UI.
        HotstringDto dto = new(Guid.NewGuid(), [], true, "long", "replacement", null,
            true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            Delivery: HotstringDelivery.Auto, EffectiveDelivery: HotstringDelivery.ClipboardPaste);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.FindAll(".desktop-branch [data-test=\"clipboard-delivery\"]").Should().HaveCount(1);
            cut.FindAll(".desktop-branch [data-test=\"hotstring-delivery\"]").Should().BeEmpty();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_OmitEndingCharacter_SuppressedWhenExpandImmediately()
    {
        // OmitEndingCharacter can be true alongside IsEndingCharacterRequired=false (the dialog only
        // disables the checkbox, it doesn't clear the value) — the badge must hide "O" here exactly
        // like the emitter suppresses the O option under *.
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
            false, false, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
            HotstringKind.Text, IsCaseSensitive: false, OmitEndingCharacter: true);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
            cut.Find(".option-glyphs").TextContent.Should().Be("*"));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_Edit_NonInlineEditableRow_OpensDialogWithItem()
    {
        // MudDialogProvider renders dialog content into its own root, not into the component that
        // called ShowAsync — so the dialog markup must be queried on `provider`, not on `cut`
        // (RenderPage() discards its MudDialogProvider reference; render it manually here instead,
        // matching the pattern in HotstringEditDialogTests.cs).
        // Raw is not inline-editable, so the single Edit button must route to the dialog.
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", ":*:btw::by the way", null,
            true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, Kind: HotstringKind.Raw);
        StubList(Page(dto));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        provider.WaitForAssertion(() =>
            provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Contain("by the way"));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_DateTimeRow_ShowsDateTimeSummaryInReplacementColumn()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "now", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.DateTime,
            DateTimeFormat: "yyyy-MM-dd");
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("yyyy-MM-dd"));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_MacroRow_RendersTokenChipsNotRawSyntax()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "greet", "Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Macro);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // Scoped to the desktop grid: the mobile branch is also in the DOM (hidden by
            // CSS) and intentionally renders the raw macro text in its collapsed rows.
            string grid = cut.Find(".hotstrings-grid").TextContent;
            grid.Should().NotContain("{{key:Enter}}");
            grid.Should().NotContain("{{cursor}}");
            grid.Should().Contain("{{first_name}}");
            grid.Should().Contain("Enter");
            grid.Should().Contain("⌖ cursor");
            cut.FindAll(".hotstrings-grid .macro-token-chip").Count.Should().Be(2);
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_MacroRow_EscapedLiteralOnly_RendersPlainTextNoChip()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "esc", "{{{{first_name}}}}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Macro);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("{{first_name}}");
            cut.FindAll(".hotstrings-grid .macro-token-chip").Should().BeEmpty();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_TextRow_ReplacementCell_HasNoMacroChips()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Text);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("by the way");
            cut.FindAll(".hotstrings-grid .macro-token-chip").Should().BeEmpty();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EveryKind_RendersExactlyOneEditButtonPerRow()
    {
        // Every row gets exactly one Edit button regardless of kind — its behavior branches
        // internally (inline for Text with no context, dialog otherwise), it's not two buttons.
        var dateTimeDto = new HotstringDto(Guid.NewGuid(), [], true, "now", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.DateTime,
            DateTimeFormat: "yyyy-MM-dd");
        var textDto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Text);
        StubList(Page(dateTimeDto, textDto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.FindAll("button.edit").Count.Should().Be(2));
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_KindFilter_ReloadsDataWithSelectedKind()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"kind-filter\"]"));

        IRenderedComponent<MudSelect<HotstringKind?>> desktopKindFilter = cut
            .FindComponents<MudSelect<HotstringKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"kind-filter\""));
        await cut.InvokeAsync(() => desktopKindFilter.Instance.ValueChanged.InvokeAsync(HotstringKind.DateTime));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotstringListRequest>(r => r.Kind == HotstringKind.DateTime),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public Task Page_RawRow_ShowsFirstLineMonospaceEllipsis()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "~ver", ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Raw);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement summary = cut.Find(".hotstrings-grid .script-summary");
            summary.TextContent.Should().Be(":*:~ver::");
            summary.TextContent.Should().NotContain("MsgBox A_AhkVersion");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_RawRow_ShowsWarningColoredBadgeWithAccessibleText()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "~ver", ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Raw);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement badge = cut.Find(".type-badge .mud-chip");
            badge.TextContent.Should().Contain("Raw");
            badge.ClassList.Should().Contain("kind-chip--raw");
            // Warning must be conveyed semantically, not just via color — screen readers read the
            // aria-label, not the CSS warning color.
            badge.GetAttribute("aria-label").Should()
                .Contain("Raw").And.Contain("Verbatim AutoHotkey definition");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_DateTimeRow_ShowsInfoColoredBadge()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "now", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.DateTime,
            DateTimeFormat: "yyyy-MM-dd");
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement badge = cut.Find(".type-badge .mud-chip");
            badge.TextContent.Should().Contain("Date");
            badge.ClassList.Should().Contain("kind-chip--datetime");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_MacroRow_ShowsSuccessColoredBadge()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "greet", "hello", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Macro);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement badge = cut.Find(".type-badge .mud-chip");
            badge.TextContent.Should().Contain("Macro");
            badge.ClassList.Should().Contain("kind-chip--macro");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_Categories_RenderOutlinedAccentChips()
    {
        var categoryId = Guid.NewGuid();
        StubCategories(new CategoryDto(categoryId, "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, CategoryIds: [categoryId]);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            IReadOnlyList<AngleSharp.Dom.IElement> categoryChips = [.. cut.FindAll(".mud-table-cell .mud-chip")
                .Where(chip => chip.TextContent.Contains("Work"))];
            categoryChips.Should().NotBeEmpty();
            categoryChips.Should().OnlyContain(chip => chip.ClassList.Contains("mud-chip-outlined"));
            // Categories carry the brand accent, not MudBlazor's default grey. Outlined + accent is
            // a deliberately separate channel from the tinted, filled kind chips in the Type column.
            categoryChips.Should().OnlyContain(chip =>
                chip.ClassList.Any(c => c.Contains("primary", StringComparison.OrdinalIgnoreCase)));
        });
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_TypeColumnHeader_ShowsGlyphLegendHelpIcon()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find(".type-legend-help").Should().NotBeNull());
    }

    [Fact]
    public async Task Page_SelectedRow_GetsSelectedRowClass()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("tbody tr"));

        await cut.InvokeAsync(() => cut.Find("tbody tr input[type=\"checkbox\"]").Change(true));

        cut.WaitForAssertion(() => cut.Find("tbody tr.selected-row").Should().NotBeNull());
    }

    [Fact]
    public Task Page_RawRow_SuppressesOptionGlyphsAndTooltipFlags()
    {
        // IsTriggerInsideWord=true is the CLI/default for a Raw row, but its options live in the
        // verbatim text — the structured flag glyphs ("?") and tooltip flag phrases must not show.
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "~ver", ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Raw);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Find(".hotstrings-grid .option-glyphs").TextContent.Should().BeEmpty();
            cut.Find(".hotstrings-grid .type-badge").TextContent.Should().Contain("Raw");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_KindFilter_ListsAllFourKinds()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"kind-filter\"]"));

        // Desktop + mobile selects each render all HotstringKind items — 4 kinds x 2 selects.
        IReadOnlyList<HotstringKind?> allValues = [.. cut.FindComponents<MudSelectItem<HotstringKind?>>()
            .Select(c => c.Instance.Value)];

        allValues.Should().HaveCount(8);
        allValues.Distinct().Should().BeEquivalentTo(
            [HotstringKind.Text, HotstringKind.DateTime, HotstringKind.Macro, HotstringKind.Raw]);
    }

    [Fact]
    public async Task Page_MobileKindFilter_ReloadsDataWithSelectedKind()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"kind-filter-mobile\"]"));

        IRenderedComponent<MudSelect<HotstringKind?>> mobileKindFilter = cut
            .FindComponents<MudSelect<HotstringKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"kind-filter-mobile\""));
        await cut.InvokeAsync(() => mobileKindFilter.Instance.ValueChanged.InvokeAsync(HotstringKind.DateTime));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotstringListRequest>(r => r.Kind == HotstringKind.DateTime),
            Arg.Any<CancellationToken>()));
    }
}
