using AHKFlowApp.Application.Queries.Hotstrings;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class ListHotstringsQueryValidatorTests
{
    private readonly ListHotstringsQueryValidator _sut = new();

    [Fact]
    public void Validate_Defaults_Succeeds()
    {
        ValidationResult result = _sut.Validate(new ListHotstringsQuery());

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Validate_WithPageLessThan1_Fails(int page)
    {
        ValidationResult result = _sut.Validate(new ListHotstringsQuery(Page: page, PageSize: 50));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Page");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(201)]
    [InlineData(1000)]
    public void Validate_WithPageSizeOutOfRange_Fails(int pageSize)
    {
        ValidationResult result = _sut.Validate(new ListHotstringsQuery(PageSize: pageSize));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "PageSize");
    }

    [Theory]
    [InlineData(1)]
    [InlineData(50)]
    [InlineData(200)]
    public void Validate_WithPageSizeAtBoundary_Succeeds(int pageSize)
    {
        ValidationResult result = _sut.Validate(new ListHotstringsQuery(PageSize: pageSize));

        result.IsValid.Should().BeTrue();
    }
}
