using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class UpdateHotstringCommandValidatorTests
{
    private readonly UpdateHotstringCommandValidator _sut = new();

    [Fact]
    public void Validate_WithValidInput_Succeeds()
    {
        var cmd = new UpdateHotstringCommand(
            Guid.NewGuid(),
            new UpdateHotstringDto("btw", "by the way", null, true, true));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyTrigger_Fails()
    {
        var cmd = new UpdateHotstringCommand(
            Guid.NewGuid(),
            new UpdateHotstringDto("", "exp", null, true, true));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_WithTriggerLongerThan50_Fails()
    {
        var cmd = new UpdateHotstringCommand(
            Guid.NewGuid(),
            new UpdateHotstringDto(new string('x', 51), "exp", null, true, true));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_WithReplacementLongerThan4000_Fails()
    {
        var cmd = new UpdateHotstringCommand(
            Guid.NewGuid(),
            new UpdateHotstringDto("btw", new string('x', 4001), null, true, true));

        ValidationResult result = _sut.Validate(cmd);

        result.IsValid.Should().BeFalse();
    }
}
