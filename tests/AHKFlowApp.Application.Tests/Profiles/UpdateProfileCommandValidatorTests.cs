using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

public sealed class UpdateProfileCommandValidatorTests
{
    private readonly UpdateProfileCommandValidator _sut = new();

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Name_required(string name)
    {
        TestValidationResult<UpdateProfileCommand> result = _sut.TestValidate(new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto(name, "", "", false)));
        result.ShouldHaveValidationErrorFor(x => x.Input.Name);
    }

    [Fact]
    public void Name_too_long()
    {
        TestValidationResult<UpdateProfileCommand> result = _sut.TestValidate(
            new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto(new string('x', 101), "", "", false)));
        result.ShouldHaveValidationErrorFor(x => x.Input.Name);
    }

    [Fact]
    public void Header_too_long()
    {
        TestValidationResult<UpdateProfileCommand> result = _sut.TestValidate(
            new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto("ok", new string('x', 8001), "", false)));
        result.ShouldHaveValidationErrorFor(x => x.Input.HeaderTemplate);
    }

    [Fact]
    public void Footer_too_long()
    {
        TestValidationResult<UpdateProfileCommand> result = _sut.TestValidate(
            new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto("ok", "", new string('x', 4001), false)));
        result.ShouldHaveValidationErrorFor(x => x.Input.FooterTemplate);
    }

    [Fact]
    public void Valid_input_passes()
    {
        TestValidationResult<UpdateProfileCommand> result = _sut.TestValidate(new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto("Work", "", "", false)));
        result.IsValid.Should().BeTrue();
    }
}
