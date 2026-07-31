using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

/// <summary>
/// Covers the window-context rules on the three hotkey validators. The rule bodies are shared with
/// hotstrings, so these tests prove the rules are wired up, and that every message reaches the
/// caller unchanged.
/// </summary>
public sealed class HotkeyWindowContextRulesTests
{
    private static ValidationResult ValidateCreate(WindowMatchType? matchType, string? value)
    {
        CreateHotkeyDto dto = new(
            Description: "Open Notepad",
            Key: "n",
            ActionKind: HotkeyActionKind.Run,
            Ctrl: true,
            RunTarget: "notepad.exe",
            RunTargetKind: RunTargetKind.Application,
            AppliesToAllProfiles: true,
            ContextMatchType: matchType,
            ContextValue: value);

        return new CreateHotkeyCommandValidator().Validate(new CreateHotkeyCommand(dto));
    }

    private static ValidationResult ValidateUpdate(WindowMatchType? matchType, string? value)
    {
        UpdateHotkeyDto dto = new(
            Description: "Open Notepad",
            Key: "n",
            ActionKind: HotkeyActionKind.Run,
            Ctrl: true,
            Alt: false,
            Shift: false,
            Win: false,
            Text: null,
            SendKeysContent: null,
            RunTarget: "notepad.exe",
            RunTargetKind: RunTargetKind.Application,
            WindowOp: null,
            RemapDest: null,
            Body: null,
            ProfileIds: null,
            AppliesToAllProfiles: true,
            ContextMatchType: matchType,
            ContextValue: value);

        return new UpdateHotkeyCommandValidator().Validate(new UpdateHotkeyCommand(Guid.NewGuid(), dto));
    }

    private static ValidationResult ValidatePreview(WindowMatchType? matchType, string? value)
    {
        HotkeyPreviewRequestDto dto = new(
            Description: "Open Notepad",
            Key: "n",
            ActionKind: HotkeyActionKind.Run,
            Ctrl: true,
            RunTarget: "notepad.exe",
            RunTargetKind: RunTargetKind.Application,
            ContextMatchType: matchType,
            ContextValue: value);

        return new GetHotkeyPreviewQueryValidator().Validate(new GetHotkeyPreviewQuery(dto));
    }

    [Theory]
    [InlineData(WindowMatchType.Executable, "notepad.exe")]
    [InlineData(WindowMatchType.WindowClass, "Notepad")]
    [InlineData(WindowMatchType.TitleContains, "Untitled")]
    [InlineData(null, null)]
    public void Create_ValidContextPair_IsAccepted(WindowMatchType? matchType, string? value)
    {
        ValidationResult result = ValidateCreate(matchType, value);

        result.IsValid.Should().BeTrue(string.Join("; ", result.Errors));
    }

    [Fact]
    public void Create_MatchTypeWithoutValue_IsRejected()
    {
        ValidationResult result = ValidateCreate(WindowMatchType.Executable, null);

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextMatchType and ContextValue must both be set or both be null.");
    }

    [Fact]
    public void Create_ValueWithoutMatchType_IsRejected()
    {
        ValidationResult result = ValidateCreate(null, "notepad.exe");

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextMatchType and ContextValue must both be set or both be null.");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_BlankValue_IsRejected(string value)
    {
        ValidationResult result = ValidateCreate(WindowMatchType.Executable, value);

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextValue must not be blank or whitespace.");
    }

    [Fact]
    public void Create_ValueOverMaxLength_IsRejected()
    {
        ValidationResult result = ValidateCreate(WindowMatchType.Executable, new string('a', 201));

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextValue must be 200 characters or fewer.");
    }

    [Fact]
    public void Create_ValueAtMaxLength_IsAccepted()
    {
        ValidationResult result = ValidateCreate(WindowMatchType.Executable, new string('a', 200));

        result.IsValid.Should().BeTrue(string.Join("; ", result.Errors));
    }

    [Fact]
    public void Create_ValueWithDoubleQuote_IsRejected()
    {
        ValidationResult result = ValidateCreate(WindowMatchType.TitleContains, "say \"hi\"");

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextValue must not contain double-quote characters.");
    }

    [Fact]
    public void Create_ValueWithBacktick_IsRejected()
    {
        ValidationResult result = ValidateCreate(WindowMatchType.TitleContains, "back`tick");

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextValue must not contain backtick characters.");
    }

    [Fact]
    public void Create_ValueWithControlCharacter_IsRejected()
    {
        ValidationResult result = ValidateCreate(WindowMatchType.TitleContains, "line\nbreak");

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextValue must not contain control characters.");
    }

    [Fact]
    public void Create_UndefinedMatchType_IsRejected()
    {
        ValidationResult result = ValidateCreate((WindowMatchType)99, "notepad.exe");

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName.EndsWith("ContextMatchType"));
    }

    [Fact]
    public void Update_MatchTypeWithoutValue_IsRejected()
    {
        ValidationResult result = ValidateUpdate(WindowMatchType.Executable, null);

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextMatchType and ContextValue must both be set or both be null.");
    }

    [Fact]
    public void Update_ValidContextPair_IsAccepted()
    {
        ValidationResult result = ValidateUpdate(WindowMatchType.Executable, "code.exe");

        result.IsValid.Should().BeTrue(string.Join("; ", result.Errors));
    }

    [Fact]
    public void Preview_MatchTypeWithoutValue_IsRejected()
    {
        ValidationResult result = ValidatePreview(WindowMatchType.Executable, null);

        result.Errors.Should().Contain(e =>
            e.ErrorMessage == "ContextMatchType and ContextValue must both be set or both be null.");
    }

    [Fact]
    public void Preview_ValidContextPair_IsAccepted()
    {
        ValidationResult result = ValidatePreview(WindowMatchType.WindowClass, "Notepad");

        result.IsValid.Should().BeTrue(string.Join("; ", result.Errors));
    }
}
