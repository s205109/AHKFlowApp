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

public sealed class HotstringsPageTests : HotstringsPageTestsBase
{
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
        cut.WaitForAssertion(() => cut.Find("button.edit"));

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

    // Backlog 169: a bulk delete of one row read "Delete 1 hotstring(s)? You can restore them".
    // No test read the delete text, so nothing caught it.
    [Fact]
    public async Task Page_BulkDeleteOfOneRow_ReadsAsSingular()
    {
        var aId = Guid.NewGuid();
        var a = new HotstringDto(aId, [], true, "a", "x", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
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

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.edit"));

        await cut.InvokeAsync(() => cut.Instance.OnSelectedItemsChanged([HotstringEditModel.FromDto(a)]));

        cut.WaitForAssertion(() => cut.Find("button.bulk-delete-hotstrings"));
        cut.Find("button.bulk-delete-hotstrings").Click();

        cut.WaitForAssertion(() => dialogService.Received(1).ShowMessageBoxAsync(
            Arg.Is<string>(t => t == "Delete hotstring?"),
            Arg.Is<string>(m => m == "Delete 1 hotstring? You can restore it from the Recycle Bin."),
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<DialogOptions>()));
        cut.WaitForAssertion(() => snackbar.Received(1).Add(
            "Deleted 1 hotstring.", Severity.Success,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));
    }

    [Fact]
    public async Task Page_DesktopBulkDelete_ClearsTheMobileBranch()
    {
        var aId = Guid.NewGuid();
        var bId = Guid.NewGuid();
        var a = new HotstringDto(aId, [], true, "aaa", "first", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        var b = new HotstringDto(bId, [], true, "bbb", "second", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
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
        cut.WaitForAssertion(() =>
            cut.Find(".mobile-branch").TextContent.Should().Contain("aaa"));

        await cut.InvokeAsync(() => cut.Instance.OnSelectedItemsChanged(
            [HotstringEditModel.FromDto(a), HotstringEditModel.FromDto(b)]));

        cut.WaitForAssertion(() => cut.Find("button.bulk-delete-hotstrings"));

        // An empty page is what the next load returns once both rows are gone.
        StubList(Page());

        cut.Find("button.bulk-delete-hotstrings").Click();

        // Both branches render at once, so the assertion names the branch it is about. Naming rows
        // that must be gone cannot pass from the initial load, unlike a bare Received() on ListAsync.
        cut.WaitForAssertion(() =>
        {
            string mobile = cut.Find(".mobile-branch").TextContent;
            mobile.Should().NotContain("aaa");
            mobile.Should().NotContain("bbb");
        });
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
}
