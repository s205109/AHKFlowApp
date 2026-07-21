using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class HotkeyRulesTests
{
    private static ValidationResult ValidateKey(string key)
    {
        CreateHotkeyDto dto = new(
            Description: "d",
            Key: key,
            Ctrl: true,
            Action: HotkeyAction.Run,
            Parameters: "notepad.exe",
            AppliesToAllProfiles: true);

        return new CreateHotkeyCommandValidator().Validate(new CreateHotkeyCommand(dto));
    }

    [Theory]
    [InlineData("a")]
    [InlineData("F5")]
    [InlineData("Escape")]
    [InlineData("Esc")]
    [InlineData("Numpad0")]
    [InlineData("Volume_Up")]
    [InlineData("vk1B")]
    [InlineData("sc001")]
    public void ValidKey_KnownKeyOrCode_IsAccepted(string key)
    {
        ValidationResult result = ValidateKey(key);

        result.Errors.Should().NotContain(e => e.PropertyName.EndsWith("Key"));
    }

    [Theory]
    [InlineData("NotAKey")]
    [InlineData("vk1Bsc001")]
    [InlineData("Joy1")]
    [InlineData("")]
    public void ValidKey_UnknownKey_IsRejected(string key)
    {
        ValidationResult result = ValidateKey(key);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName.EndsWith("Key"));
    }

    [Theory]
    [InlineData(" a")]
    [InlineData("a ")]
    public void ValidKey_SurroundingWhitespace_IsStillRejected(string key)
    {
        ValidationResult result = ValidateKey(key);

        result.IsValid.Should().BeFalse();
    }
}
