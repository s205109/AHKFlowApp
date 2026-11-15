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

public abstract class HotstringsPageTestsBase : BunitContext, IAsyncLifetime
{
    protected readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();
    protected readonly IProfilesApiClient _profilesApi = Substitute.For<IProfilesApiClient>();
    protected readonly ICategoriesApiClient _categoriesApi = Substitute.For<ICategoriesApiClient>();

    protected static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    protected HotstringsPageTestsBase()
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

    protected IRenderedComponent<Hotstrings> RenderPage()
    {
        Render<MudPopoverProvider>();
        Render<MudDialogProvider>();
        return Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    protected static PagedList<HotstringDto> Page(params HotstringDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    protected void StubList(PagedList<HotstringDto> page) =>
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Ok(page));

    protected void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<HotstringListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Failure(status, problem));

    protected void StubProfiles(params ProfileDto[] profiles) =>
        _profilesApi.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    protected void StubCategories(params CategoryDto[] categories)
    {
        PagedList<CategoryDto> page = new(categories, 1, 200, categories.Length, 1, false, false);
        _categoriesApi.ListAsync(Arg.Any<CategoryListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<CategoryDto>>.Ok(page));
    }

    protected static void StartDraftEdit(IRenderedComponent<Hotstrings> cut)
    {
        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
    }

    protected static void FillRequiredFields(IRenderedComponent<Hotstrings> cut, string trigger = "btw", string replacement = "by the way")
    {
        cut.Find("input[data-test=\"trigger-input\"]").Input(trigger);
        cut.Find("textarea[data-test=\"replacement-input\"]").Input(replacement);
    }
}
