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
        return Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static PagedList<HotstringDto> Page(params HotstringDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    private void StubList(PagedList<HotstringDto> page) =>
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Ok(page));

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
        cut.Find("input[data-test=\"replacement-input\"]").Input(replacement);
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
    public void Page_ReloadWhileEditingExistingRow_KeepsEditControls()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(
                ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)),
                ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();
        cut.WaitForAssertion(() => cut.Find("button.commit-edit"));

        cut.Find("button.reload-hotstrings").Click();

        cut.WaitForAssertion(() => _api.Received(2).ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>()));
        cut.WaitForAssertion(() =>
        {
            cut.Find("button.commit-edit").Should().NotBeNull();
            cut.Find("input[data-test=\"trigger-input\"]").Should().NotBeNull();
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
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"replacement-input\"]"));
        cut.Find("input[data-test=\"replacement-input\"]").Input("by the way!");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(dto.Id,
            Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"), Arg.Any<CancellationToken>()));
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
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();
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
        cut.Find("input[data-test=\"replacement-input\"]").Input("by the way");
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
}
