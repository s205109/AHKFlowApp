using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class CreateHotstringCommandValidatorTests
{
    private readonly CreateHotstringCommandValidator _sut = new();

    private static CreateHotstringCommand Cmd(
        string trigger = "btw",
        string replacement = "by the way",
        bool appliesToAllProfiles = true,
        Guid[]? profileIds = null)
        => new(new CreateHotstringDto(trigger, replacement, profileIds, appliesToAllProfiles));

    [Fact]
    public void Validate_WithAppliesToAllProfiles_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd());

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithValidProfileIds_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(
            appliesToAllProfiles: false,
            profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyTrigger_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger is required.");
    }

    [Fact]
    public void Validate_WithWhitespaceTrigger_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: "   "));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Fact]
    public void Validate_WithTriggerAt50Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 50)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt51Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 51)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must be 50 characters or fewer.");
    }

    [Theory]
    [InlineData(" btw")]
    [InlineData("btw ")]
    [InlineData(" btw ")]
    public void Validate_WithTriggerLeadingOrTrailingWhitespace_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("bt\nw")]
    [InlineData("bt\rw")]
    [InlineData("bt\tw")]
    public void Validate_WithTriggerContainingControlChars_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not contain line breaks or tabs.");
    }

    [Theory]
    [InlineData("dür")]
    [InlineData("café")]
    [InlineData("niño")]
    public void Validate_WithUnicodeTrigger_Succeeds(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyReplacement_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement is required.");
    }

    [Fact]
    public void Validate_WithReplacementAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithReplacementAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(replacement: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_AppliesToAllWithProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            appliesToAllProfiles: true,
            profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ProfileIds must be empty when AppliesToAllProfiles is true.");
    }

    [Fact]
    public void Validate_NotAppliesToAllWithNoProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            appliesToAllProfiles: false,
            profileIds: null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "At least one profile must be specified when AppliesToAllProfiles is false.");
    }

    [Fact]
    public void Validate_ProfileIdsContainsEmptyGuid_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            appliesToAllProfiles: false,
            profileIds: [Guid.Empty]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ProfileIds must not contain empty GUIDs.");
    }
}
