using AHKFlowApp.Application.Commands.KnownShortcuts;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using FluentValidation.Results;
using Xunit;

namespace AHKFlowApp.Application.Tests.Validation;

public sealed class CreateCustomKnownShortcutCommandValidatorTests
{
    private readonly CreateCustomKnownShortcutCommandValidator _validator = new();

    public static TheoryData<string> BannedTerms()
    {
        TheoryData<string> data = [];
        foreach (string term in ShortcutWording.BannedTerms)
            data.Add(term);
        return data;
    }

    [Fact]
    public void Validate_ValidRecord_Passes()
    {
        _validator.Validate(Command()).IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_EmptyKey_Fails()
    {
        Result(Command(key: "")).Should().Contain(e => e.ErrorMessage == "Pick a key.");
    }

    [Fact]
    public void Validate_UnknownKey_Fails()
    {
        Result(Command(key: "NotAKey")).Should()
            .Contain(e => e.ErrorMessage == "That is not a key AHKFlow can use in a hotkey.");
    }

    [Fact]
    public void Validate_EmptyUsedBy_Fails()
    {
        Result(Command(usedBy: "")).Should().Contain(e => e.ErrorMessage == "Say what uses these keys.");
    }

    [Fact]
    public void Validate_UsedByOverSixtyCharacters_Fails()
    {
        _validator.Validate(Command(usedBy: new string('a', 61))).IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_EmptyDoes_Fails()
    {
        Result(Command(does: "")).Should().Contain(e => e.ErrorMessage == "Say what the keys do.");
    }

    [Fact]
    public void Validate_DoesOverTwoHundredCharacters_Fails()
    {
        _validator.Validate(Command(does: new string('a', 201))).IsValid.Should().BeFalse();
    }

    [Fact]
    public void Validate_ProtectionProtected_Fails()
    {
        Result(Command(protection: ShortcutProtection.Protected)).Should()
            .Contain(e => e.ErrorMessage == "Only built-in records can say Windows handles the keys itself.");
    }

    [Theory]
    [InlineData(ShortcutProtection.Normal)]
    [InlineData(ShortcutProtection.Unknown)]
    public void Validate_ProtectionAnOwnerCanClaim_Passes(ShortcutProtection protection)
    {
        _validator.Validate(Command(protection: protection)).IsValid.Should().BeTrue();
    }

    [Fact]
    public void Validate_DoesStartsWithACapital_Fails()
    {
        Result(Command(does: "Open the settings window")).Should()
            .Contain(e => e.ErrorMessage == "What it does must start with a lowercase verb, like \"open the settings window\".");
    }

    [Fact]
    public void Validate_DoesStartsWithACapitalAfterASpace_Fails()
    {
        // The handler trims before storing, so leading whitespace must not hide the capital.
        Result(Command(does: "  Open the settings window")).Should()
            .Contain(e => e.ErrorMessage == "What it does must start with a lowercase verb, like \"open the settings window\".");
    }

    [Theory]
    [InlineData("open the settings window")]
    [InlineData("open Visual Studio")]
    [InlineData("3D view toggle")]
    [InlineData("open whenever the window is focused")]
    [InlineData("open the window")]
    [InlineData("toggle Always On Top")]
    [InlineData("keep the window always-on-top")]
    [InlineData("switch to the Willow theme")]
    [InlineData("open the user’s folder")]
    public void Validate_AcceptableDoesPhrases_Pass(string does)
    {
        _validator.Validate(Command(does: does)).IsValid.Should().BeTrue(does);
    }

    [Theory]
    [MemberData(nameof(BannedTerms))]
    public void Validate_DoesMakesAnAbsoluteClaim_Fails(string term)
    {
        Result(Command(does: $"open the window and {term} close it")).Should()
            .Contain(e => e.ErrorMessage == "Say what the keys do, not what will or will not happen.");
    }

    // Backlog 207: the rule refused "will not open the panel" but accepted "will open the panel"
    // and "always opens the panel". These rows are written by hand, not read from BannedTerms,
    // so a word missing from the list fails here. The theory above proves only that every listed
    // word is enforced.
    [Theory]
    [InlineData("will open the panel")]
    [InlineData("open the panel, and it will stay open")]
    [InlineData("open the panel so you'll see it")]
    [InlineData("open the panel so it’ll stay open")]
    [InlineData("will not open the panel")]
    [InlineData("won't open the panel")]
    [InlineData("won’t open the panel")]
    [InlineData("always open the panel")]
    [InlineData("always opens the panel")]
    [InlineData("open the panel, ALWAYS")]
    [InlineData("never open the panel")]
    [InlineData("cannot be overridden")]
    [InlineData("can not be overridden")]
    [InlineData("can't be overridden")]
    [InlineData("can’t be overridden")]
    public void Validate_DoesPromisesAnOutcome_Fails(string does)
    {
        Result(Command(does: does)).Should()
            .Contain(e => e.ErrorMessage == "Say what the keys do, not what will or will not happen.", does);
    }

    [Fact]
    public void BannedTerms_AreAllCaughtByTheRule()
    {
        // The array and the regex list the same terms. A term added to one and not the other
        // would otherwise be silently unenforced.
        ShortcutWording.BannedTerms.Should().OnlyContain(t => ShortcutWording.MakesAbsoluteClaim(t));
    }

    private List<ValidationFailure> Result(CreateCustomKnownShortcutCommand command) =>
        _validator.Validate(command).Errors;

    private static CreateCustomKnownShortcutCommand Command(
        string key = "F7",
        string usedBy = "Visual Studio",
        string does = "open the command palette",
        ShortcutProtection protection = ShortcutProtection.Unknown) =>
        new(new CreateCustomKnownShortcutDto(
            key, Ctrl: true, Alt: false, Shift: false, Win: false,
            usedBy, ShortcutScope.Foreground, does, protection));
}
