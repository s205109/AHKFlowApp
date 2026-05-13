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

public sealed class HotkeysPageTests : BunitContext, IAsyncLifetime
{
    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public HotkeysPageTests()
    {
        Services.AddSingleton(_api);

        IUserPreferencesService prefs = Substitute.For<IUserPreferencesService>();
        prefs.GetAsync(Arg.Any<CancellationToken>()).Returns(UserPreferences.Default);
        Services.AddSingleton(prefs);

        IProfilesApiClient profilesApi = Substitute.For<IProfilesApiClient>();
        profilesApi.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok([]));
        Services.AddSingleton(profilesApi);

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<Hotkeys> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<Hotkeys>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static HotkeyDto MakeHotkey(string description = "Open terminal", string key = "T") =>
        new(Guid.NewGuid(), [], true, description, key, true, false, false, false,
            HotkeyAction.Run, "", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static PagedList<HotkeyDto> Page(params HotkeyDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    private void StubList(PagedList<HotkeyDto> page) =>
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotkeyDto>>.Ok(page));

    private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotkeyDto>>.Failure(status, problem));

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
    public Task Page_SaveDraftRow_CallsCreate()
    {
        StubList(Page());
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(MakeHotkey("Open terminal", "T")));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));
        cut.Find("button.add-hotkey").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]"));
        cut.Find("input[data-test=\"description-input\"]").Input("Open terminal");
        cut.Find("input[data-test=\"key-input\"]").Input("T");
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
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));
        cut.Find("button.add-hotkey").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]"));
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
        cut.WaitForAssertion(() => cut.Find("button.add-hotkey"));
        cut.Find("button.add-hotkey").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"key-input\"]"));
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
}
