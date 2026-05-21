using AHKFlowApp.Application.Commands.Categories;
using AHKFlowApp.Application.DTOs;
using FluentValidation.TestHelper;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

public sealed class CreateCategoryCommandValidatorTests
{
    private readonly CreateCategoryCommandValidator _sut = new();

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Rejects_EmptyOrWhitespaceName(string name)
    {
        TestValidationResult<CreateCategoryCommand> result =
            _sut.TestValidate(new CreateCategoryCommand(new CreateCategoryDto(name)));
        result.ShouldHaveValidationErrorFor(c => c.Input.Name);
    }

    [Fact]
    public void Rejects_NameLongerThan30Chars()
    {
        string name = new('x', 31);
        TestValidationResult<CreateCategoryCommand> result =
            _sut.TestValidate(new CreateCategoryCommand(new CreateCategoryDto(name)));
        result.ShouldHaveValidationErrorFor(c => c.Input.Name);
    }

    [Fact]
    public void Accepts_ValidName()
    {
        TestValidationResult<CreateCategoryCommand> result =
            _sut.TestValidate(new CreateCategoryCommand(new CreateCategoryDto("Email")));
        result.ShouldNotHaveAnyValidationErrors();
    }
}
