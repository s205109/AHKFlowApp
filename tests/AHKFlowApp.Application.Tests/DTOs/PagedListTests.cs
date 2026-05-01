using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.DTOs;

public sealed class PagedListTests
{
    [Fact]
    public void TotalPages_WhenPageSizeIsZero_ReturnsZero()
    {
        var paged = new PagedList<int>([], Page: 1, PageSize: 0, TotalCount: 10);

        paged.TotalPages.Should().Be(0);
    }

    [Fact]
    public void TotalPages_RoundsUpPartialPage()
    {
        var paged = new PagedList<int>([], Page: 1, PageSize: 3, TotalCount: 7);

        paged.TotalPages.Should().Be(3);
    }

    [Fact]
    public void HasNextPage_WhenOnLastPage_ReturnsFalse()
    {
        var paged = new PagedList<int>([], Page: 3, PageSize: 3, TotalCount: 7);

        paged.HasNextPage.Should().BeFalse();
    }

    [Fact]
    public void HasNextPage_WhenNotOnLastPage_ReturnsTrue()
    {
        var paged = new PagedList<int>([], Page: 1, PageSize: 3, TotalCount: 7);

        paged.HasNextPage.Should().BeTrue();
    }

    [Fact]
    public void HasPreviousPage_WhenOnFirstPage_ReturnsFalse()
    {
        var paged = new PagedList<int>([], Page: 1, PageSize: 10, TotalCount: 5);

        paged.HasPreviousPage.Should().BeFalse();
    }

    [Fact]
    public void HasPreviousPage_WhenPastFirstPage_ReturnsTrue()
    {
        var paged = new PagedList<int>([], Page: 2, PageSize: 10, TotalCount: 25);

        paged.HasPreviousPage.Should().BeTrue();
    }
}
