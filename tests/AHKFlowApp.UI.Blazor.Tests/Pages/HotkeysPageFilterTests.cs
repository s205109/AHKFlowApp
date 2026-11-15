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

public sealed class HotkeysPageFilterTests : HotkeysPageTestsBase
{
    [Fact]
    public void Page_HasSearchInput()
    {
        StubList(Page());

        IRenderedComponent<Hotkeys> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find(".search-hotkeys").Should().NotBeNull());
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
}
