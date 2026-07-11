using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class GetHotstringPreviewQueryValidatorTests
{
    private readonly GetHotstringPreviewQueryValidator _sut = new();

    private static GetHotstringPreviewQuery Query(
        string trigger = "btw",
        string replacement = "by the way",
        HotstringKind kind = HotstringKind.Text,
        string? dateTimeFormat = null,
        WindowMatchType? contextMatchType = null,
        string? contextValue = null)
        => new(new HotstringPreviewRequestDto(
            kind,
            trigger,
            replacement,
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: true,
            DateTimeFormat: dateTimeFormat,
            ContextMatchType: contextMatchType,
            ContextValue: contextValue));

    [Fact]
    public void Validate_ContextMatchTypeWithoutValue_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            contextMatchType: WindowMatchType.Executable,
            contextValue: null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ContextMatchType" &&
            e.ErrorMessage == "ContextMatchType and ContextValue must both be set or both be null.");
    }

    [Fact]
    public void Validate_ContextBothSet_Passes()
    {
        ValidationResult result = _sut.Validate(Query(
            contextMatchType: WindowMatchType.Executable,
            contextValue: "notepad.exe"));

        result.Errors.Should().NotContain(e =>
            e.PropertyName == "Input.ContextMatchType" || e.PropertyName == "Input.ContextValue");
    }

    [Fact]
    public void Validate_ContextValueEmpty_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            contextMatchType: WindowMatchType.Executable,
            contextValue: ""));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ContextValue" &&
            e.ErrorMessage == "ContextValue must not be blank or whitespace.");
    }

    [Fact]
    public void Validate_ContextValueWhitespaceOnly_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            contextMatchType: WindowMatchType.Executable,
            contextValue: "   "));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.ContextValue" &&
            e.ErrorMessage == "ContextValue must not be blank or whitespace.");
    }
}
