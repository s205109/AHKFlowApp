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
}
