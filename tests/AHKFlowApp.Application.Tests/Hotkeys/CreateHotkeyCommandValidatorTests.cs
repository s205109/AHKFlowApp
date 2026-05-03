using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class CreateHotkeyCommandValidatorTests
{
    private readonly CreateHotkeyCommandValidator _sut = new();

    private static CreateHotkeyCommand Cmd(
        string description = "Open Notepad",
        string key = "n",
        bool ctrl = true,
        bool alt = false,
        bool shift = false,
        bool win = false,
        HotkeyAction action = HotkeyAction.Run,
        string parameters = "notepad.exe",
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true)
        => new(new CreateHotkeyDto(description, key, ctrl, alt, shift, win, action, parameters, profileIds, appliesToAllProfiles));

    [Fact]
    public void Validate_WithValidInput_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd());

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithEmptyDescription_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(description: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Description" &&
            e.ErrorMessage == "Description is required.");
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
    public void Validate_WithEmptyKey_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(key: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key is required.");
    }

    [Fact]
    public void Validate_WithKeyAt20Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(key: new string('x', 20)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithKeyAt21Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(key: new string('x', 21)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key must be 20 characters or fewer.");
    }

    [Theory]
    [InlineData(" n")]
    [InlineData("n ")]
    [InlineData(" n ")]
    public void Validate_WithKeyLeadingOrTrailingWhitespace_Fails(string key)
    {
        ValidationResult result = _sut.Validate(Cmd(key: key));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key must not have leading or trailing whitespace.");
    }

    [Theory]
    [InlineData("n\r")]
    [InlineData("n\n")]
    [InlineData("n\t")]
    public void Validate_WithKeyContainingControlChars_Fails(string key)
    {
        ValidationResult result = _sut.Validate(Cmd(key: key));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Key" &&
            e.ErrorMessage == "Key must not contain line breaks or tabs.");
    }

    [Fact]
    public void Validate_WithParametersAt4000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(parameters: new string('x', 4000)));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_WithParametersAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(parameters: new string('x', 4001)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Parameters" &&
            e.ErrorMessage == "Parameters must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_WithInvalidAction_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(action: (HotkeyAction)999));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Action" &&
            e.ErrorMessage == "Action must be a valid HotkeyAction value.");
    }

    [Fact]
    public void Validate_AppliesToAllProfiles_WithProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(
            Cmd(appliesToAllProfiles: true, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ProfileIds" &&
            e.ErrorMessage == "ProfileIds must be empty when AppliesToAllProfiles is true.");
    }

    [Fact]
    public void Validate_NotAppliesToAll_WithNoProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(
            Cmd(appliesToAllProfiles: false, profileIds: null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ProfileIds" &&
            e.ErrorMessage == "At least one profile must be specified when AppliesToAllProfiles is false.");
    }

    [Fact]
    public void Validate_NotAppliesToAll_WithEmptyGuidInProfileIds_Fails()
    {
        ValidationResult result = _sut.Validate(
            Cmd(appliesToAllProfiles: false, profileIds: [Guid.Empty]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ProfileIds" &&
            e.ErrorMessage == "ProfileIds must not contain empty GUIDs.");
    }

    [Fact]
    public void Validate_NotAppliesToAll_WithValidProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(
            Cmd(appliesToAllProfiles: false, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeTrue();
    }
}
