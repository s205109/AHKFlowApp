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
        string? contextValue = null,
        string? description = null,
        HotstringDelivery delivery = HotstringDelivery.Auto)
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
            ContextValue: contextValue,
            Description: description,
            Delivery: delivery));

    [Fact]
    public void Validate_TextAutoAt4001Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Query(
            replacement: new string('x', 4001),
            delivery: HotstringDelivery.Auto));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_TextTypeAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            replacement: new string('x', 4001),
            delivery: HotstringDelivery.Type));

        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_TextClipboardAt100000Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Query(
            replacement: new string('x', 100_000),
            delivery: HotstringDelivery.ClipboardPaste));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_TextClipboardAt100001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            replacement: new string('x', 100_001),
            delivery: HotstringDelivery.ClipboardPaste));

        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 100000 characters or fewer.");
    }

    [Fact]
    public void Validate_MacroAt4001Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            kind: HotstringKind.Macro,
            replacement: new string('x', 4001)));

        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Replacement" &&
            e.ErrorMessage == "Replacement must be 4000 characters or fewer.");
    }

    [Fact]
    public void Validate_NonTextWithExplicitDelivery_Fails()
    {
        ValidationResult result = _sut.Validate(Query(
            kind: HotstringKind.Macro,
            delivery: HotstringDelivery.ClipboardPaste));

        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Delivery" &&
            e.ErrorMessage == "Delivery must be Auto unless Kind is Text.");
    }

    [Fact]
    public void Validate_InvalidDelivery_Fails()
    {
        ValidationResult result = _sut.Validate(Query(delivery: (HotstringDelivery)99));

        result.Errors.Should().Contain(e => e.PropertyName == "Input.Delivery");
    }

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

    [Fact]
    public void GetHotstringPreviewQueryValidator_RawKind_OverlongDescription_Fails()
    {
        // The base 200-char Description rule applies to every kind (matching save), so an over-long
        // typed Description on a Raw item fails preview instead of previewing then failing save.
        ValidationResult result = _sut.Validate(Query(
            kind: HotstringKind.Raw,
            replacement: "::btw::by the way",
            description: new string('x', 201)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Description" &&
            e.ErrorMessage == "Description must be 200 characters or fewer.");
    }

    [Fact]
    public void GetHotstringPreviewQueryValidator_RawKind_Accepted()
    {
        ValidationResult result = _sut.Validate(Query(
            kind: HotstringKind.Raw,
            replacement: ":K1000 SE*:ftw::for the win"));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.Kind");
        result.Errors.Should().NotContain(e => e.PropertyName == "Input.Replacement");
    }

    [Fact]
    public void GetHotstringPreviewQueryValidator_RawKind_EmptyClientTrigger_PassesTriggerGate()
    {
        ValidationResult result = _sut.Validate(Query(
            trigger: "",
            kind: HotstringKind.Raw,
            replacement: "::btw::by the way"));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.Trigger");
    }
}
