using AHKFlowApp.Application.Queries.Categories;
using FluentValidation.TestHelper;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

public sealed class ListCategoriesQueryValidatorTests
{
    private readonly ListCategoriesQueryValidator _sut = new();

    [Theory]
    [InlineData(0)]
    [InlineData(10001)]
    public void Rejects_OutOfRange_Page(int page)
        => _sut.TestValidate(new ListCategoriesQuery(Page: page))
            .ShouldHaveValidationErrorFor(q => q.Page);

    [Theory]
    [InlineData(0)]
    [InlineData(201)]
    public void Rejects_OutOfRange_PageSize(int pageSize)
        => _sut.TestValidate(new ListCategoriesQuery(PageSize: pageSize))
            .ShouldHaveValidationErrorFor(q => q.PageSize);

    [Fact]
    public void Rejects_Search_LongerThan200Chars()
        => _sut.TestValidate(new ListCategoriesQuery(Search: new string('x', 201)))
            .ShouldHaveValidationErrorFor(q => q.Search);

    [Fact]
    public void Accepts_Defaults()
        => _sut.TestValidate(new ListCategoriesQuery())
            .ShouldNotHaveAnyValidationErrors();
}
