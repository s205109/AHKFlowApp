using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

/// <summary>
/// The definition validators and the Update command validators must refuse the same values.
/// They share every rule implementation but compose the list separately, so a rule added to one
/// and not the other would bring back exactly the gap backlog 162 closed: a value Update refuses
/// and Restore accepts.
/// <para>
/// The comparison anchors on the Update validators, while the acceptance criterion names Create
/// and Update. That is enough: <c>CreateHotstringCommandValidator</c> and
/// <c>UpdateHotstringCommandValidator</c> hold the same rule list, and so do
/// <c>CreateHotkeyCommandValidator</c> and <c>UpdateHotkeyCommandValidator</c>. A rule added to
/// Create alone would be a different gap, and it is not one these tests claim to catch.
/// </para>
/// <para>
/// These tests compare messages, not identifiers. FluentValidation names the Update side
/// <c>Input.ContextValue</c>, because the rule reads through the command's DTO, and the definition
/// side <c>ContextValue</c>. The message is the part both sides must agree on.
/// </para>
/// <para>
/// Every case sets <c>AppliesToAllProfiles</c> true with no profile ids. That satisfies the
/// profile-association rules, which the definition validators leave out on purpose, so the two
/// sets stay comparable without filtering anything out.
/// </para>
/// <para>
/// Each case arrives as its name, not as a definition. xUnit1044 is an error in this repository,
/// and neither definition record is serializable, so a record passed through
/// <c>MemberData</c> fails the build.
/// </para>
/// </summary>
[Trait("Category", "Unit")]
public sealed class DefinitionRuleParityTests
{
    private static string[] Messages(IEnumerable<Ardalis.Result.ValidationError> errors) =>
        [.. errors.Select(e => e.ErrorMessage).Order()];

    private static string[] Messages(ValidationResult result) =>
        [.. result.Errors.Select(f => f.ErrorMessage).Order()];

    private static HotstringDefinition TextDefinition(string trigger, string replacement) =>
        new(
            Trigger: trigger,
            Replacement: replacement,
            Description: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false);

    private static HotkeyDefinition RunDefinition() =>
        new(
            Description: "Open Notepad",
            Key: "n",
            Ctrl: true,
            Alt: false,
            Shift: false,
            Win: false,
            ActionKind: HotkeyActionKind.Run,
            AppliesToAllProfiles: true,
            RunTarget: "notepad.exe",
            RunTargetKind: RunTargetKind.Application);

    /// <summary>The definition each case name stands for, and whether it must fail the rules.</summary>
    private static (bool ExpectFailures, HotstringDefinition Definition) HotstringCase(string name) => name switch
    {
        "valid Text" => (false, TextDefinition("btw", "by the way")),

        "double quote in the window context" => (true, TextDefinition("btw", "by the way") with
        {
            ContextMatchType = WindowMatchType.TitleContains,
            ContextValue = "a \" b",
        }),

        "trigger with trailing whitespace" => (true, TextDefinition("btw ", "by the way")),

        "description over the cap" => (true, TextDefinition("btw", "by the way") with
        {
            Description = new string('x', 600),
        }),

        "DateTime with no format" => (true, TextDefinition("today", "") with
        {
            Kind = HotstringKind.DateTime,
            DateTimeFormat = null,
        }),

        "valid DateTime" => (false, TextDefinition("today", "") with
        {
            Kind = HotstringKind.DateTime,
            DateTimeFormat = "yyyy-MM-dd",
        }),

        "valid Raw" => (false, TextDefinition("ignored", ":*:ver::\n{\nMsgBox A_AhkVersion\n}") with
        {
            Kind = HotstringKind.Raw,
        }),

        "Raw whose derived trigger is too long" =>
            (true, TextDefinition("ignored", $":*:{new string('a', 45)}::\nMsgBox 1") with
            {
                Kind = HotstringKind.Raw,
            }),

        // The brace body is opened on its own line on purpose. Without the "{" line the first
        // line is bare, so ClassifyBody returns its "add a replacement" error and never reaches
        // ScanBraceBody. Only this shape puts the naive brace counter on the parity axis.
        "Raw with unbalanced braces" =>
            (true, TextDefinition("ignored", ":*:lb::\n{\nSend \"{{}\"\n}") with
            {
                Kind = HotstringKind.Raw,
            }),

        "Macro with an empty replacement" => (true, TextDefinition("mac", "") with
        {
            Kind = HotstringKind.Macro,
        }),

        // Fails a rule only AddMacroKindRules adds. The empty-replacement case above fails
        // ValidReplacement from the Date & time group instead, so without this case the Macro
        // group could be dropped from one validator and every case would stay green.
        "Macro with a key token after the cursor" =>
            (true, TextDefinition("mac", "a{{cursor}}b{{key:Enter}}") with
            {
                Kind = HotstringKind.Macro,
            }),

        // Fails a rule only AddDeliveryRules adds. Every other case leaves Delivery at Auto,
        // which that group accepts for every kind.
        "Macro with a non-Auto delivery" => (true, TextDefinition("mac", "hello") with
        {
            Kind = HotstringKind.Macro,
            Delivery = HotstringDelivery.ClipboardPaste,
        }),

        _ => throw new ArgumentOutOfRangeException(nameof(name), name, "Unknown case."),
    };

    /// <summary>The definition each case name stands for, and whether it must fail the rules.</summary>
    private static (bool ExpectFailures, HotkeyDefinition Definition) HotkeyCase(string name) => name switch
    {
        "valid Run" => (false, RunDefinition()),

        "key outside the registry" => (true, RunDefinition() with { Key = "NotAKeyName" }),

        "Remap with no destination" => (true, RunDefinition() with
        {
            ActionKind = HotkeyActionKind.Remap,
            RunTarget = null,
            RunTargetKind = null,
            RemapDest = null,
        }),

        "backtick in the window context" => (true, RunDefinition() with
        {
            ContextMatchType = WindowMatchType.TitleContains,
            ContextValue = "a ` b",
        }),

        "Raw body with unbalanced braces" => (true, RunDefinition() with
        {
            ActionKind = HotkeyActionKind.Raw,
            RunTarget = null,
            RunTargetKind = null,
            Body = "Send(\"{{}\")",
        }),

        "valid Raw body" => (false, RunDefinition() with
        {
            ActionKind = HotkeyActionKind.Raw,
            RunTarget = null,
            RunTargetKind = null,
            Body = "MsgBox \"hi\"",
        }),

        "SendText carrying a foreign field" => (true, RunDefinition() with
        {
            ActionKind = HotkeyActionKind.SendText,
            Text = "hello",
            RunTarget = "notepad.exe",
            RunTargetKind = RunTargetKind.Application,
        }),

        "empty description" => (true, RunDefinition() with { Description = "" }),

        _ => throw new ArgumentOutOfRangeException(nameof(name), name, "Unknown case."),
    };

    private static UpdateHotstringDto ToUpdateDto(HotstringDefinition d) =>
        new(
            Trigger: d.Trigger,
            Replacement: d.Replacement,
            ProfileIds: [],
            AppliesToAllProfiles: d.AppliesToAllProfiles,
            IsEndingCharacterRequired: d.IsEndingCharacterRequired,
            IsTriggerInsideWord: d.IsTriggerInsideWord,
            Description: d.Description,
            Kind: d.Kind,
            IsCaseSensitive: d.IsCaseSensitive,
            OmitEndingCharacter: d.OmitEndingCharacter,
            DateTimeFormat: d.DateTimeFormat,
            DateOffsetAmount: d.DateOffsetAmount,
            DateOffsetUnit: d.DateOffsetUnit,
            ContextMatchType: d.ContextMatchType,
            ContextValue: d.ContextValue,
            Delivery: d.Delivery);

    private static UpdateHotkeyDto ToUpdateDto(HotkeyDefinition d) =>
        new(
            Description: d.Description,
            Key: d.Key,
            ActionKind: d.ActionKind,
            Ctrl: d.Ctrl,
            Alt: d.Alt,
            Shift: d.Shift,
            Win: d.Win,
            Text: d.Text,
            SendKeysContent: d.SendKeysContent,
            RunTarget: d.RunTarget,
            RunTargetKind: d.RunTargetKind,
            WindowOp: d.WindowOp,
            RemapDest: d.RemapDest,
            Body: d.Body,
            ProfileIds: [],
            AppliesToAllProfiles: d.AppliesToAllProfiles,
            ContextMatchType: d.ContextMatchType,
            ContextValue: d.ContextValue);

    [Theory]
    [InlineData("valid Text")]
    [InlineData("double quote in the window context")]
    [InlineData("trigger with trailing whitespace")]
    [InlineData("description over the cap")]
    [InlineData("DateTime with no format")]
    [InlineData("valid DateTime")]
    [InlineData("valid Raw")]
    [InlineData("Raw whose derived trigger is too long")]
    [InlineData("Raw with unbalanced braces")]
    [InlineData("Macro with an empty replacement")]
    [InlineData("Macro with a key token after the cursor")]
    [InlineData("Macro with a non-Auto delivery")]
    public void HotstringDefinitionRules_MatchTheUpdateCommandRules(string caseName)
    {
        (bool expectFailures, HotstringDefinition definition) = HotstringCase(caseName);

        string[] fromDefinition = Messages(DefinitionRuleCheck.Check(definition));
        string[] fromUpdate = Messages(new UpdateHotstringCommandValidator()
            .Validate(new UpdateHotstringCommand(Guid.NewGuid(), ToUpdateDto(definition))));

        fromDefinition.Should().Equal(fromUpdate,
            "Restore and Revert must refuse exactly what Update refuses");

        if (expectFailures)
        {
            fromDefinition.Should().NotBeEmpty(
                "the case would prove nothing if neither validator objected");
        }
        else
        {
            fromDefinition.Should().BeEmpty("a valid definition must pass both validators");
        }
    }

    [Theory]
    [InlineData("valid Run")]
    [InlineData("key outside the registry")]
    [InlineData("Remap with no destination")]
    [InlineData("backtick in the window context")]
    [InlineData("Raw body with unbalanced braces")]
    [InlineData("valid Raw body")]
    [InlineData("SendText carrying a foreign field")]
    [InlineData("empty description")]
    public void HotkeyDefinitionRules_MatchTheUpdateCommandRules(string caseName)
    {
        (bool expectFailures, HotkeyDefinition definition) = HotkeyCase(caseName);

        string[] fromDefinition = Messages(DefinitionRuleCheck.Check(definition));
        string[] fromUpdate = Messages(new UpdateHotkeyCommandValidator()
            .Validate(new UpdateHotkeyCommand(Guid.NewGuid(), ToUpdateDto(definition))));

        fromDefinition.Should().Equal(fromUpdate,
            "Restore and Revert must refuse exactly what Update refuses");

        if (expectFailures)
        {
            fromDefinition.Should().NotBeEmpty(
                "the case would prove nothing if neither validator objected");
        }
        else
        {
            fromDefinition.Should().BeEmpty("a valid definition must pass both validators");
        }
    }
}
