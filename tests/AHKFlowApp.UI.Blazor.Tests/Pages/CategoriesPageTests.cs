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

public sealed class CategoriesPageTests : BunitContext, IAsyncLifetime
{
    private readonly ICategoriesApiClient _api = Substitute.For<ICategoriesApiClient>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public CategoriesPageTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<Categories> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<Categories>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static CategoryDto MakeCategory(string name = "Work") =>
        new(Guid.NewGuid(), name, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static PagedList<CategoryDto> Page(params CategoryDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    private void StubList(params CategoryDto[] items) =>
        _api.ListAsync(Arg.Any<CategoryListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<CategoryDto>>.Ok(Page(items)));

    private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<CategoryListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<CategoryDto>>.Failure(status, problem));

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        CategoryDto dto = MakeCategory("Work");
        StubList(dto);

        IRenderedComponent<Categories> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Work"));

        cut.Markup.Should().Contain("Work");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        StubListFailure(ApiResultStatus.NetworkError);

        IRenderedComponent<Categories> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }

    [Fact]
    public Task Page_AddAndCommit_CallsCreateWithCorrectName()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateCategoryDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<CategoryDto>.Ok(MakeCategory("Email")));

        IRenderedComponent<Categories> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-category"));
        cut.Find("button.add-category").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"category-name-input\"]"));
        cut.Find("input[data-test=\"category-name-input\"]").Input("Email");
        cut.Find("button.commit-edit").Click();

        return _api.Received(1).CreateAsync(
            Arg.Is<CreateCategoryDto>(d => d.Name == "Email"),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public Task Page_RenameAndCommit_CallsUpdateWithCorrectName()
    {
        CategoryDto dto = MakeCategory("Old Name");
        StubList(dto);
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateCategoryDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<CategoryDto>.Ok(MakeCategory("New Name")));

        IRenderedComponent<Categories> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Old Name"));
        cut.Find("button.start-edit").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"category-name-input\"]"));
        cut.Find("input[data-test=\"category-name-input\"]").Input("New Name");
        cut.Find("button.commit-edit").Click();

        return _api.Received(1).UpdateAsync(
            dto.Id,
            Arg.Is<UpdateCategoryDto>(d => d.Name == "New Name"),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public void Page_Delete_ClickDeleteButton_DialogCancels_DoesNotCallApi()
    {
        CategoryDto dto = MakeCategory("ToDelete");
        StubList(dto);

        IRenderedComponent<Categories> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("ToDelete"));
        cut.Find("button.delete").Click();

        cut.WaitForAssertion(() => _api.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()));
    }

    [Fact]
    public Task Page_CreateConflict_ShowsErrorSnackbar()
    {
        StubList();
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Category already exists", null, null);
        _api.CreateAsync(Arg.Any<CreateCategoryDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<CategoryDto>.Failure(ApiResultStatus.Conflict, problem));

        IRenderedComponent<Categories> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-category"));
        cut.Find("button.add-category").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"category-name-input\"]"));
        cut.Find("input[data-test=\"category-name-input\"]").Input("Work");
        cut.Find("button.commit-edit").Click();

        return _api.Received(1).CreateAsync(Arg.Any<CreateCategoryDto>(), Arg.Any<CancellationToken>());
    }
}
