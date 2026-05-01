using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class CreateHotkeyCommandValidatorTests
{
    private readonly CreateHotkeyCommandValidator _sut = new();

    private static CreateHotkeyCommand Cmd(
        string trigger = "^!K",
        string action = "Run notepad",
        string? description = null,
        Guid? profileId = null)
        => new(new CreateHotkeyDto(trigger, action, description, profileId));

    [Fact]
    public void Validate_WithValidInput_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd());

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
    public void Validate_WithTriggerAt100Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 100)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithTriggerAt101Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: new string('x', 101)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must be 100 characters or fewer.");
    }

    [Theory]
    [InlineData(" ^!K")]
    [InlineData("^!K ")]
    [InlineData(" ^!K ")]
    public void Validate_WithTriggerLeadingOrTrailingWhitespace_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("^!\nK")]
    [InlineData("^!\rK")]
    [InlineData("^!\tK")]
    public void Validate_WithTriggerContainingControlChars_Fails(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Trigger" &&
            e.ErrorMessage == "Trigger must not contain line breaks or tabs.");
    }

    [Theory]
    [InlineData("^!Numpad0 & F12")]
    [InlineData("F1")]
    [InlineData("#k")]
    public void Validate_WithTypicalAhkSyntax_Succeeds(string trigger)
    {
        ValidationResult result = _sut.Validate(Cmd(trigger: trigger));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyAction_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(action: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Action" &&
            e.ErrorMessage == "Action is required.");
    }

    [Fact]
    public void Validate_WithActionAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(action: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithActionAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(action: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Action" &&
            e.ErrorMessage == "Action must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_WithDescriptionAt200Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(description: new string('x', 200)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithDescriptionAt201Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(description: new string('x', 201)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Description" &&
            e.ErrorMessage == "Description must be 200 characters or fewer.");
    }

    [Fact]
    public void Validate_WithNullDescription_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(description: null));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyGuidProfileId_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: Guid.Empty));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ProfileId" &&
            e.ErrorMessage == "ProfileId must not be an empty GUID.");
    }

    [Fact]
    public void Validate_WithNullProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: null));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithValidProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(profileId: Guid.NewGuid()));

        result.IsValid.Should().BeTrue();
    }
}
