using AHKFlowApp.Application.Queries.Hotkeys;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class ListHotkeysQueryValidatorTests
{
    private readonly ListHotkeysQueryValidator _sut = new();

    [Fact]
    public void Validate_Defaults_Succeeds()
    {
        ValidationResult result = _sut.Validate(new ListHotkeysQuery());

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Validate_WithPageLessThan1_Fails(int page)
    {
        ValidationResult result = _sut.Validate(new ListHotkeysQuery(Page: page, PageSize: 50));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Page");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(201)]
    [InlineData(1000)]
    public void Validate_WithPageSizeOutOfRange_Fails(int pageSize)
    {
        ValidationResult result = _sut.Validate(new ListHotkeysQuery(PageSize: pageSize));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "PageSize");
    }

    [Theory]
    [InlineData(1)]
    [InlineData(50)]
    [InlineData(200)]
    public void Validate_WithPageSizeAtBoundary_Succeeds(int pageSize)
    {
        ValidationResult result = _sut.Validate(new ListHotkeysQuery(PageSize: pageSize));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithSearchTooLong_Fails()
    {
        string longSearch = new('x', 201);

        ValidationResult result = _sut.Validate(new ListHotkeysQuery(Search: longSearch));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Search");
    }

    [Fact]
    public void Validate_WithSearchAtMaxLength_Succeeds()
    {
        string maxSearch = new('x', 200);

        ValidationResult result = _sut.Validate(new ListHotkeysQuery(Search: maxSearch));

        result.IsValid.Should().BeTrue();
    }
}
