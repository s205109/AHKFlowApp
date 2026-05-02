using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class UpdateHotkeyCommandValidatorTests
{
    private readonly UpdateHotkeyCommandValidator _sut = new();

    private static UpdateHotkeyCommand Cmd(
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
        => new(Guid.NewGuid(), new UpdateHotkeyDto(description, key, ctrl, alt, shift, win, action, parameters, profileIds, appliesToAllProfiles));

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
    public void Validate_WithDescriptionTooLong_Fails()
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
    public void Validate_NotAppliesToAll_WithValidProfileId_Succeeds()
    {
        ValidationResult result = _sut.Validate(
            Cmd(appliesToAllProfiles: false, profileIds: [Guid.NewGuid()]));

        result.IsValid.Should().BeTrue();
    }
}
