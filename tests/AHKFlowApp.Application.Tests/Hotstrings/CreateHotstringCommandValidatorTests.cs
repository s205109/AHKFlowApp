using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class CreateHotstringCommandValidatorTests
{
    private readonly CreateHotstringCommandValidator _sut = new();

    [Fact]
    public void Validate_WithValidInput_Succeeds()
    {
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", "by the way"));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Validate_WithEmptyTrigger_Fails(string trigger)
    {
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(trigger, "exp"));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Trigger");
    }

    [Fact]
    public void Validate_WithTriggerLongerThan50_Fails()
    {
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(new string('x', 51), "exp"));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Trigger");
    }

    [Fact]
    public void Validate_WithEmptyReplacement_Fails()
    {
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", ""));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Replacement");
    }

    [Fact]
    public void Validate_WithReplacementLongerThan4000_Fails()
    {
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", new string('x', 4001)));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Replacement");
    }
}
