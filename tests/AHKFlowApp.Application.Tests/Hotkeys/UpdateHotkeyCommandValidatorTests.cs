using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class UpdateHotkeyCommandValidatorTests
{
    private readonly UpdateHotkeyCommandValidator _sut = new();

    private static UpdateHotkeyCommand Cmd(
        string trigger = "^!K",
        string action = "Run notepad",
        string? description = null,
        Guid? profileId = null)
        => new(Guid.NewGuid(), new UpdateHotkeyDto(trigger, action, description, profileId));

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
    public void Validate_WithEmptyAction_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(action: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Action" &&
            e.ErrorMessage == "Action is required.");
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
}
