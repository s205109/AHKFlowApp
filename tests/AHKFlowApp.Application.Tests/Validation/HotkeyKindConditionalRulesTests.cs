using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class HotkeyKindConditionalRulesTests
{
    private const int PayloadMaxLength = 4000;

    private static readonly string[] s_payloadFields =
        ["Text", "SendKeysContent", "RunTarget", "RunTargetKind", "WindowOp", "RemapDest", "Body"];

    private static ValidationResult Validate(CreateHotkeyDto dto) =>
        new CreateHotkeyCommandValidator().Validate(new CreateHotkeyCommand(dto));

    // AppliesToAllProfiles: true keeps the profile-association rules quiet, so every failure below
    // belongs to the action payload and the single-error assertions mean what they say.
    private static CreateHotkeyDto Base(HotkeyActionKind kind) =>
        new("d", "a", kind, Ctrl: true, AppliesToAllProfiles: true);

    /// <summary>The minimal payload each kind requires and nothing else.</summary>
    private static CreateHotkeyDto Valid(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => Base(kind) with { Text = "hello" },
        HotkeyActionKind.SendKeys => Base(kind) with { SendKeysContent = "{Volume_Up}" },
        HotkeyActionKind.Run => Base(kind) with { RunTarget = "notepad.exe", RunTargetKind = RunTargetKind.Application },
        HotkeyActionKind.Window => Base(kind) with { WindowOp = WindowOp.Minimize },
        HotkeyActionKind.Remap => Base(kind) with { RemapDest = "Escape" },
        HotkeyActionKind.Disable => Base(kind),
        HotkeyActionKind.Raw => Base(kind) with { Body = "MsgBox 1" },
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    private static CreateHotkeyDto WithField(CreateHotkeyDto dto, string field) => field switch
    {
        "Text" => dto with { Text = "hello" },
        "SendKeysContent" => dto with { SendKeysContent = "{Volume_Up}" },
        "RunTarget" => dto with { RunTarget = "notepad.exe" },
        "RunTargetKind" => dto with { RunTargetKind = RunTargetKind.Application },
        "WindowOp" => dto with { WindowOp = WindowOp.Minimize },
        "RemapDest" => dto with { RemapDest = "Escape" },
        "Body" => dto with { Body = "MsgBox 1" },
        _ => throw new ArgumentOutOfRangeException(nameof(field)),
    };

    private static HotkeyActionKind Owner(string field) => field switch
    {
        "Text" => HotkeyActionKind.SendText,
        "SendKeysContent" => HotkeyActionKind.SendKeys,
        "RunTarget" or "RunTargetKind" => HotkeyActionKind.Run,
        "WindowOp" => HotkeyActionKind.Window,
        "RemapDest" => HotkeyActionKind.Remap,
        "Body" => HotkeyActionKind.Raw,
        _ => throw new ArgumentOutOfRangeException(nameof(field)),
    };

    public static TheoryData<HotkeyActionKind> AllKinds()
    {
        TheoryData<HotkeyActionKind> data = [];
        foreach (HotkeyActionKind kind in Enum.GetValues<HotkeyActionKind>())
            data.Add(kind);
        return data;
    }

    /// <summary>Every (kind, field) pair where the field belongs to a different kind.</summary>
    public static TheoryData<HotkeyActionKind, string> ForeignFieldPairs()
    {
        TheoryData<HotkeyActionKind, string> data = [];
        foreach (HotkeyActionKind kind in Enum.GetValues<HotkeyActionKind>())
        {
            foreach (string field in s_payloadFields)
            {
                if (Owner(field) != kind)
                    data.Add(kind, field);
            }
        }

        return data;
    }

    // --- Both directions, every kind ------------------------------------------------------

    [Theory]
    [MemberData(nameof(AllKinds))]
    public void EveryKind_WithOnlyItsOwnPayload_IsValid(HotkeyActionKind kind) =>
        Validate(Valid(kind)).IsValid.Should().BeTrue();

    [Theory]
    [MemberData(nameof(ForeignFieldPairs))]
    public void EveryKind_CarryingAForeignField_IsInvalid(HotkeyActionKind kind, string field)
    {
        ValidationResult result = Validate(WithField(Valid(kind), field));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == field &&
            e.ErrorMessage == $"{field} is only valid for the {Owner(field)} action.");
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Text")]
    [InlineData(HotkeyActionKind.SendKeys, "SendKeysContent")]
    [InlineData(HotkeyActionKind.Run, "RunTarget")]
    [InlineData(HotkeyActionKind.Window, "WindowOp")]
    [InlineData(HotkeyActionKind.Remap, "RemapDest")]
    [InlineData(HotkeyActionKind.Raw, "Body")]
    public void EveryKind_WithNoPayloadAtAll_FailsOnItsOwnField(HotkeyActionKind kind, string field)
    {
        ValidationResult result = Validate(Base(kind));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == field);
    }

    // --- Run: two required fields, two distinct failures ----------------------------------

    [Fact]
    public void Run_WithoutTarget_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Run)).IsValid.Should().BeFalse();

    [Fact]
    public void Run_WithTarget_IsValid() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad.exe", RunTargetKind = RunTargetKind.Application })
            .IsValid.Should().BeTrue();

    // The two Run failures are separate fields. A merged check would blame RunTarget for a bad
    // RunTargetKind, and the client would highlight a control it filled in correctly.
    [Fact]
    public void Run_WithoutTarget_FailsOnRunTarget() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTargetKind = RunTargetKind.Application })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("RunTarget");

    [Fact]
    public void Run_WithoutTargetKind_FailsOnRunTargetKind() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad.exe" })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("RunTargetKind");

    [Fact]
    public void Run_UndefinedTargetKind_FailsOnRunTargetKind() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad.exe", RunTargetKind = (RunTargetKind)99 })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("RunTargetKind");

    [Fact]
    public void Run_WithForeignField_IsInvalid() =>  // both-or-neither: Run must not carry Body
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "x", RunTargetKind = RunTargetKind.Application, Body = "MsgBox 1" })
            .IsValid.Should().BeFalse();

    // --- Token grammars -------------------------------------------------------------------

    [Fact]
    public void SendKeys_InvalidToken_IsInvalid() =>
        Validate(Base(HotkeyActionKind.SendKeys) with { SendKeysContent = "Volume_Up" }) // must be braced
            .IsValid.Should().BeFalse();

    [Fact]
    public void SendKeys_ValidToken_IsValid() =>
        Validate(Base(HotkeyActionKind.SendKeys) with { SendKeysContent = "{Volume_Up}" }).IsValid.Should().BeTrue();

    [Fact]
    public void Remap_InvalidDest_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Remap) with { RemapDest = "Pause" }).IsValid.Should().BeFalse();

    [Fact]
    public void Remap_ValidDest_IsValid() =>
        Validate(Base(HotkeyActionKind.Remap) with { RemapDest = "Escape" }).IsValid.Should().BeTrue();

    [Fact]
    public void Window_WithoutOp_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Window)).IsValid.Should().BeFalse();

    [Fact]
    public void Disable_TakesNoFields_IsValid() =>
        Validate(Base(HotkeyActionKind.Disable)).IsValid.Should().BeTrue();

    // --- Undefined enum values ------------------------------------------------------------

    // Undefined enum ints deserialize happily; the validator, not the emitter, must reject them.
    [Fact]
    public void UndefinedActionKind_IsInvalid() =>
        Validate(Base((HotkeyActionKind)99)).IsValid.Should().BeFalse();

    [Fact]
    public void UndefinedActionKind_FailsOnActionKind() =>
        Validate(Base((HotkeyActionKind)99))
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("ActionKind");

    [Fact]
    public void UndefinedWindowOp_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Window) with { WindowOp = (WindowOp)99 }).IsValid.Should().BeFalse();

    [Fact]
    public void UndefinedRunTargetKind_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Run) with { RunTarget = "notepad", RunTargetKind = (RunTargetKind)99 })
            .IsValid.Should().BeFalse();

    [Fact] // RunTargetKind is a foreign field outside Run
    public void SendText_WithRunTargetKind_IsInvalid() =>
        Validate(Base(HotkeyActionKind.SendText) with { Text = "hi", RunTargetKind = RunTargetKind.Url })
            .IsValid.Should().BeFalse();

    // --- Raw body -------------------------------------------------------------------------

    [Fact]
    public void Raw_HashDirective_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Raw) with { Body = "#SingleInstance Force" }).IsValid.Should().BeFalse();

    [Fact]
    public void Raw_UnbalancedBraces_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Raw) with { Body = "MsgBox 1 }" }).IsValid.Should().BeFalse();

    // The emitter writes Body verbatim (2026-07-22 decision), so a block body supplies its own outer
    // braces. Counting braces — rather than assuming an emitter-added wrapper — accepts that form.
    [Fact]
    public void Raw_SelfBracedBlockBody_IsValid() =>
        Validate(Base(HotkeyActionKind.Raw) with { Body = "{\n    MsgBox 1\n}" }).IsValid.Should().BeTrue();

    [Fact]
    public void Raw_IndentedHashDirective_IsInvalid() =>
        Validate(Base(HotkeyActionKind.Raw) with { Body = "{\n    #Requires AutoHotkey v2\n}" }).IsValid.Should().BeFalse();

    // --- Free-text limits carried over from the retired ValidParameters rule ---------------

    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Text")]
    [InlineData(HotkeyActionKind.Run, "RunTarget")]
    [InlineData(HotkeyActionKind.Raw, "Body")]
    public void FreeTextField_AtMaxLength_IsValid(HotkeyActionKind kind, string field)
    {
        CreateHotkeyDto dto = WithLongValue(kind, field, PayloadMaxLength);

        Validate(dto).IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Text")]
    [InlineData(HotkeyActionKind.Run, "RunTarget")]
    [InlineData(HotkeyActionKind.Raw, "Body")]
    public void FreeTextField_OverMaxLength_IsInvalid(HotkeyActionKind kind, string field)
    {
        CreateHotkeyDto dto = WithLongValue(kind, field, PayloadMaxLength + 1);

        ValidationResult result = Validate(dto);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == field &&
            e.ErrorMessage == $"{field} must be {PayloadMaxLength} characters or fewer.");
    }

    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Text")]
    [InlineData(HotkeyActionKind.Run, "RunTarget")]
    [InlineData(HotkeyActionKind.Raw, "Body")]
    public void FreeTextField_WithControlCharacter_IsInvalid(HotkeyActionKind kind, string field)
    {
        CreateHotkeyDto dto = WithValue(kind, field, "bad\0value");

        ValidationResult result = Validate(dto);

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e =>
            e.PropertyName == field &&
            e.ErrorMessage == $"{field} must not contain control characters.");
    }

    // AhkEscaping represents exactly these three at emission, so they stay legal input.
    [Theory]
    [InlineData("line one\nline two")]
    [InlineData("col\tcol")]
    [InlineData("carriage\rreturn")]
    [InlineData("he said \"hi\" 100`%")]
    public void SendText_WithEscapableCharacters_IsValid(string text) =>
        Validate(Base(HotkeyActionKind.SendText) with { Text = text }).IsValid.Should().BeTrue();

    [Fact]
    public void Run_WithDriveLetterPathAndArguments_IsValid() =>
        Validate(Base(HotkeyActionKind.Run) with
        {
            RunTarget = @"C:\tools\app.exe --flag",
            RunTargetKind = RunTargetKind.Application,
        }).IsValid.Should().BeTrue();

    // --- The update path runs the same rules ----------------------------------------------

    // Same rule set, second validator. Wired separately, so it can regress separately.
    private static ValidationResult ValidateUpdate(UpdateHotkeyDto dto) =>
        new UpdateHotkeyCommandValidator().Validate(new UpdateHotkeyCommand(Guid.NewGuid(), dto));

    private static UpdateHotkeyDto UpdateBase(HotkeyActionKind kind) =>
        new("d", "a", kind, Ctrl: true, Alt: false, Shift: false, Win: false,
            Text: null, SendKeysContent: null, RunTarget: null, RunTargetKind: null,
            WindowOp: null, RemapDest: null, Body: null,
            ProfileIds: null, AppliesToAllProfiles: true);

    [Fact]
    public void Update_WindowWithoutOp_IsInvalid() =>
        ValidateUpdate(UpdateBase(HotkeyActionKind.Window))
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("WindowOp");

    [Fact]
    public void Update_SendTextCarryingForeignBody_IsInvalid() =>
        ValidateUpdate(UpdateBase(HotkeyActionKind.SendText) with { Text = "hi", Body = "MsgBox 1" })
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("Body");

    [Fact]
    public void Update_UndefinedActionKind_IsInvalid() =>
        ValidateUpdate(UpdateBase((HotkeyActionKind)99))
            .Errors.Should().ContainSingle().Which.PropertyName.Should().Be("ActionKind");

    [Fact]
    public void Update_WithOnlyItsOwnPayload_IsValid() =>
        ValidateUpdate(UpdateBase(HotkeyActionKind.Remap) with { RemapDest = "Escape" })
            .IsValid.Should().BeTrue();

    private static CreateHotkeyDto WithLongValue(HotkeyActionKind kind, string field, int length) =>
        WithValue(kind, field, new string('x', length));

    private static CreateHotkeyDto WithValue(HotkeyActionKind kind, string field, string value)
    {
        CreateHotkeyDto dto = Valid(kind);
        return field switch
        {
            "Text" => dto with { Text = value },
            "RunTarget" => dto with { RunTarget = value },
            "Body" => dto with { Body = value },
            _ => throw new ArgumentOutOfRangeException(nameof(field)),
        };
    }
}
