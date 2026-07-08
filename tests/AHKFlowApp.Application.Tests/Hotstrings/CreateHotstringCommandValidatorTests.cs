using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
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
        Guid[]? profileIds = null,
        string? description = null,
        HotstringKind kind = HotstringKind.Text,
        string? dateTimeFormat = null,
        int? dateOffsetAmount = null,
        DateOffsetUnit? dateOffsetUnit = null)
        => new(new CreateHotstringDto(
            trigger,
            replacement,
            profileIds,
            appliesToAllProfiles,
            Description: description,
            Kind: kind,
            DateTimeFormat: dateTimeFormat,
            DateOffsetAmount: dateOffsetAmount,
            DateOffsetUnit: dateOffsetUnit));

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
    public void Validate_WithNullDescription_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(description: null));

        result.IsValid.Should().BeTrue();
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

    [Fact]
    public void Validate_ProfileIdsContainsDuplicates_Fails()
    {
        var id = Guid.NewGuid();

        ValidationResult result = _sut.Validate(Cmd(
            appliesToAllProfiles: false,
            profileIds: [id, id]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ProfileIds must not contain duplicates.");
    }

    [Fact]
    public void Kind_Text_Passes()
    {
        ValidationResult result = _sut.Validate(Cmd(kind: HotstringKind.Text));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.Kind");
    }

    [Fact]
    public void Kind_DateTime_Passes()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: "yyyy-MM-dd"));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.Kind");
        result.Errors.Should().NotContain(e => e.PropertyName == "Input.Replacement");
    }

    [Theory]
    [InlineData(HotstringKind.Macro)]
    [InlineData(HotstringKind.Script)]
    public void Kind_MacroOrScript_Fails(HotstringKind kind)
    {
        ValidationResult result = _sut.Validate(Cmd(kind: kind));

        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.Kind" &&
            e.ErrorMessage == "Only Text and Date & time hotstrings are supported.");
    }

    [Fact]
    public void DateTimeKind_WithNonEmptyReplacement_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "not empty",
            dateTimeFormat: "yyyy-MM-dd"));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.Replacement");
    }

    [Fact]
    public void DateTimeKind_WithNullDateTimeFormat_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateTimeFormat");
    }

    [Fact]
    public void TextKind_WithNonNullDateTimeFormat_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.Text,
            dateTimeFormat: "yyyy-MM-dd"));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateTimeFormat");
    }

    [Fact]
    public void TextKind_WithNonNullDateOffsetAmountOrUnit_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.Text,
            dateOffsetAmount: 1,
            dateOffsetUnit: DateOffsetUnit.Days));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateOffsetAmount");
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateOffsetUnit");
    }

    [Fact]
    public void DateTimeKind_OffsetAmountZero_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: "yyyy-MM-dd",
            dateOffsetAmount: 0,
            dateOffsetUnit: DateOffsetUnit.Days));

        result.Errors.Should().NotContain(e =>
            e.PropertyName == "Input.DateOffsetAmount" || e.PropertyName == "Input.DateOffsetUnit");
    }

    [Fact]
    public void DateTimeKind_OffsetAmountWithoutUnit_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: "yyyy-MM-dd",
            dateOffsetAmount: 1,
            dateOffsetUnit: null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == "Input.DateOffsetAmount" &&
            e.ErrorMessage == "DateOffsetAmount and DateOffsetUnit must both be set or both be null.");
    }

    [Theory]
    [InlineData(-3650)]
    [InlineData(3650)]
    public void DateTimeKind_OffsetAmountAtBounds_Succeeds(int amount)
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: "yyyy-MM-dd",
            dateOffsetAmount: amount,
            dateOffsetUnit: DateOffsetUnit.Days));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.DateOffsetAmount");
    }

    [Theory]
    [InlineData(-3651)]
    [InlineData(3651)]
    public void DateTimeKind_OffsetAmountBeyondBounds_Fails(int amount)
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: "yyyy-MM-dd",
            dateOffsetAmount: amount,
            dateOffsetUnit: DateOffsetUnit.Days));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateOffsetAmount");
    }

    [Theory]
    [InlineData("yyyy-MM-dd")]
    [InlineData("dd-MM-yyyy")]
    [InlineData("MM/dd/yyyy")]
    [InlineData("dddd d MMMM yyyy")]
    [InlineData("ddd d MMM yyyy")]
    [InlineData("MMMM yyyy")]
    [InlineData("HH:mm")]
    [InlineData("HH:mm:ss")]
    [InlineData("h:mm tt")]
    [InlineData("yyyy-MM-dd HH:mm")]
    [InlineData("yyyy-MM-dd HH:mm:ss")]
    [InlineData("yyyyMMdd-HHmmss")]
    public void DateTimeFormat_CuratedPresets_Pass(string format)
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: format));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.DateTimeFormat");
    }

    [Theory]
    [InlineData("\"yyyy\"")]
    [InlineData("`yyyy`")]
    [InlineData("'yyyy'")]
    [InlineData("yyyy\\MM")]
    [InlineData("yyyy%MM")]
    [InlineData("yyyy;MM")]
    [InlineData("yyyy{0}")]
    [InlineData("yyyy\nMM")]
    [InlineData("yyyy fMM")]
    [InlineData("yyyy zMM")]
    [InlineData("yyyy KMM")]
    [InlineData("yyyy nMM")]
    [InlineData("")]
    [InlineData("---")]
    public void DateTimeFormat_InvalidValues_Fail(string format)
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: format));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateTimeFormat");
    }

    [Fact]
    public void DateTimeFormat_At51Chars_Fails()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: new string('y', 51)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Input.DateTimeFormat");
    }

    [Fact]
    public void DateTimeFormat_At50Chars_Succeeds()
    {
        ValidationResult result = _sut.Validate(Cmd(
            kind: HotstringKind.DateTime,
            replacement: "",
            dateTimeFormat: new string('y', 50)));

        result.Errors.Should().NotContain(e => e.PropertyName == "Input.DateTimeFormat");
    }
}
