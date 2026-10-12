using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

[Trait("Category", "Unit")]
public sealed class DefinitionRuleCheckTests
{
    private static HotstringDefinition TextDefinition(
        string trigger = "btw",
        string replacement = "by the way",
        WindowMatchType? contextMatchType = null,
        string? contextValue = null) =>
        new(
            Trigger: trigger,
            Replacement: replacement,
            Description: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false,
            Kind: HotstringKind.Text,
            ContextMatchType: contextMatchType,
            ContextValue: contextValue);

    [Fact]
    public void Check_ValidTextDefinition_ReturnsNoFailures()
    {
        DefinitionRuleCheck.Check(TextDefinition()).Should().BeEmpty();
    }

    [Fact]
    public void Check_ContextValueWithDoubleQuote_ReturnsFailure()
    {
        ValidationError[] failures = DefinitionRuleCheck.Check(
            TextDefinition(contextMatchType: WindowMatchType.TitleContains, contextValue: "a \" b"));

        failures.Select(f => f.ErrorMessage).Should()
            .Contain("ContextValue must not contain double-quote characters.");
    }

    [Fact]
    public void Check_TriggerWithTrailingWhitespace_ReturnsFailure()
    {
        DefinitionRuleCheck.Check(TextDefinition(trigger: "btw "))
            .Select(f => f.ErrorMessage)
            .Should().Contain("Trigger must not have leading or trailing whitespace.");
    }

    // Review Focus 1: an Owner needs every failing rule, not only the first.
    [Fact]
    public void Check_DefinitionFailingTwoRules_ReturnsBothFailures()
    {
        ValidationError[] failures = DefinitionRuleCheck.Check(TextDefinition(
            trigger: "btw ",
            contextMatchType: WindowMatchType.TitleContains,
            contextValue: "a \" b"));

        failures.Select(f => f.ErrorMessage).Should()
            .Contain("Trigger must not have leading or trailing whitespace.")
            .And.Contain("ContextValue must not contain double-quote characters.");
    }

    // Review Focus 2: a stored Raw definition is already normalized. Re-checking it must pass,
    // or every Raw restore in the system starts failing.
    [Fact]
    public void Check_ValidRawDefinition_ReturnsNoFailures()
    {
        HotstringDefinition raw = TextDefinition() with
        {
            Kind = HotstringKind.Raw,
            Trigger = "ver",
            Replacement = ":*:ver::\n{\nMsgBox A_AhkVersion\n}",
        };

        DefinitionRuleCheck.Check(raw).Should().BeEmpty();
    }

    [Fact]
    public void Check_RawDefinitionWithTriggerOver40Chars_ReturnsFailure()
    {
        string longTrigger = new('a', 41);
        HotstringDefinition raw = TextDefinition() with
        {
            Kind = HotstringKind.Raw,
            Trigger = longTrigger,
            Replacement = $":*:{longTrigger}::\n{{\nMsgBox 1\n}}",
        };

        DefinitionRuleCheck.Check(raw)
            .Select(f => f.ErrorMessage)
            .Should().Contain("Trigger must be 40 characters or fewer.");
    }

    [Fact]
    public void Check_DateTimeKindWithNullFormat_ReturnsFailure()
    {
        HotstringDefinition dt = TextDefinition() with
        {
            Kind = HotstringKind.DateTime,
            Replacement = "",
            DateTimeFormat = null,
        };

        DefinitionRuleCheck.Check(dt)
            .Select(f => f.ErrorMessage)
            .Should().Contain("DateTimeFormat is required.");
    }

    // A legacy Kind=Script body holding AHK's own literal-brace idiom. The brace counter in
    // AddRawKindRules is deliberately string-unaware (decision D12), so it reads this as
    // unbalanced even though AHK accepts it. This test pins which way that goes for a stored
    // Snapshot, because the answer decides whether an Owner can repair the item afterwards.
    // ADR-0021 records the consequence.
    [Fact]
    public void Check_LegacyScriptBodyWithLiteralBrace_PinsTheNaiveBraceCounter()
    {
#pragma warning disable CS0618 // Script is read only from stored legacy snapshots, never new payloads.
        HotstringSnapshot legacy = new(
            Trigger: "lb", Replacement: "Send \"{{}\"", Description: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: false, IsTriggerInsideWord: false,
            ProfileIds: [], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            Kind: HotstringKind.Script);
#pragma warning restore CS0618

        ValidationError[] failures = DefinitionRuleCheck.Check(
            ScriptToRawComposer.ToDefinition(legacy));

        failures.Select(f => f.ErrorMessage).Should()
            .Contain("Raw definition must have balanced braces.");
    }

    private static HotkeyDefinition RunDefinition(string key = "n") =>
        new(
            Description: "Open Notepad",
            Key: key,
            Ctrl: true,
            Alt: false,
            Shift: false,
            Win: false,
            ActionKind: HotkeyActionKind.Run,
            AppliesToAllProfiles: true,
            RunTarget: "notepad.exe",
            RunTargetKind: RunTargetKind.Application);

    [Fact]
    public void Check_ValidHotkeyDefinition_ReturnsNoFailures()
    {
        DefinitionRuleCheck.Check(RunDefinition()).Should().BeEmpty();
    }

    [Fact]
    public void Check_HotkeyKeyNotInRegistry_ReturnsFailure()
    {
        DefinitionRuleCheck.Check(RunDefinition(key: "NotAKeyName"))
            .Select(f => f.ErrorMessage)
            .Should().Contain(m => m.StartsWith("Key must be a known key name"));
    }

    [Fact]
    public void Check_RemapWithNoDestination_ReturnsFailure()
    {
        HotkeyDefinition remap = RunDefinition() with
        {
            ActionKind = HotkeyActionKind.Remap,
            RunTarget = null,
            RunTargetKind = null,
            RemapDest = null,
        };

        DefinitionRuleCheck.Check(remap).Should().NotBeEmpty(
            "the emitter throws on a Remap with no destination, so the rules must catch it first");
    }

    [Fact]
    public void Check_HotkeyContextValueWithBacktick_ReturnsFailure()
    {
        HotkeyDefinition bad = RunDefinition() with
        {
            ContextMatchType = WindowMatchType.TitleContains,
            ContextValue = "a ` b",
        };

        DefinitionRuleCheck.Check(bad)
            .Select(f => f.ErrorMessage)
            .Should().Contain("ContextValue must not contain backtick characters.");
    }

    [Fact]
    public void Check_LegacyHotkeySendWithLiteralBrace_PinsTheNaiveBraceCounter()
    {
        // The hotkey twin of the hotstring pin above. "{{}" is how AHK's Send types a literal
        // brace, so an Owner could store it. IsValidSendKeysContent refuses it, because its
        // braced token holds a second brace, so the converter takes the Raw arm and builds the
        // body Send("{{}"). BracesBalanced then counts two opens and one close.
        HotkeySnapshot legacy = new(
            Description: "Type a brace", Key: "n",
            Ctrl: true, Alt: false, Shift: false, Win: false,
            AppliesToAllProfiles: true,
            ProfileIds: [], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            Action: LegacyHotkeyDefinitionConverter.HotkeyAction.Send,
            Parameters: "{{}");

        ValidationError[] failures = DefinitionRuleCheck.Check(
            LegacyHotkeySnapshotConverter.ToDefinition(legacy));

        failures.Select(f => f.ErrorMessage).Should()
            .Contain("Raw body braces are unbalanced.");
    }
}
