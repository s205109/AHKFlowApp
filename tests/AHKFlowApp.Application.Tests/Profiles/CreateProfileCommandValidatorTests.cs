using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

public sealed class CreateProfileCommandValidatorTests
{
    private readonly CreateProfileCommandValidator _sut = new();

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Name_required(string name)
    {
        TestValidationResult<CreateProfileCommand> result = _sut.TestValidate(new CreateProfileCommand(new CreateProfileDto(name)));
        result.ShouldHaveValidationErrorFor(x => x.Input.Name);
    }

    [Fact]
    public void Name_too_long()
    {
        TestValidationResult<CreateProfileCommand> result = _sut.TestValidate(
            new CreateProfileCommand(new CreateProfileDto(new string('x', 101))));
        result.ShouldHaveValidationErrorFor(x => x.Input.Name);
    }

    [Fact]
    public void Header_too_long()
    {
        TestValidationResult<CreateProfileCommand> result = _sut.TestValidate(
            new CreateProfileCommand(new CreateProfileDto("ok", HeaderTemplate: new string('x', 8001))));
        result.ShouldHaveValidationErrorFor(x => x.Input.HeaderTemplate);
    }

    [Fact]
    public void Footer_too_long()
    {
        TestValidationResult<CreateProfileCommand> result = _sut.TestValidate(
            new CreateProfileCommand(new CreateProfileDto("ok", FooterTemplate: new string('x', 4001))));
        result.ShouldHaveValidationErrorFor(x => x.Input.FooterTemplate);
    }

    [Fact]
    public void Valid_input_passes()
    {
        TestValidationResult<CreateProfileCommand> result = _sut.TestValidate(new CreateProfileCommand(new CreateProfileDto("Work")));
        result.IsValid.Should().BeTrue();
    }
}
