using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class TemplateUseTextTests
{
    // The notice must never promise an outcome. CONTEXT.md:99 rules that out, and the AutoHotkey
    // docs say "eclipsed" without promising it in every case.
    private static readonly string[] BannedTerms = ["never", "will not", "cannot", "won't", "can't"];

    private static TemplateHotkey Wildcard(string key) => new(key, true, false, false, false, false);

    private static ProfileTemplateUse Header(string profile, params TemplateHotkey[] hotkeys) =>
        new(profile, hotkeys, []);

    private static ProfileTemplateUse Footer(string profile, params TemplateHotkey[] hotkeys) =>
        new(profile, [], hotkeys);

    private static ProfileTemplateUse Both(string profile, TemplateHotkey hotkey) =>
        new(profile, [hotkey], [hotkey]);

    // A bare row, the way a hotkey with no modifiers reaches the notice.
    private static RowCombination Row(string key) => new(key, false, false, false, false, key);

    [Fact]
    public void TextFor_ReturnsNullWhenNoTemplateUsesTheKey()
    {
        TemplateUseText.TextFor([Header("Work", Wildcard("ScrollLock"))], Row("CapsLock")).Should().BeNull();
    }

    [Fact]
    public void TextFor_ReturnsNullWhenTheRowHasNoKey()
    {
        TemplateUseText.TextFor([Header("Work", Wildcard("CapsLock"))], Row("")).Should().BeNull();
    }

    [Fact]
    public void TextFor_NamesOneProfileAndItsHeader()
    {
        TemplateUseText.TextFor([Header("Work", Wildcard("CapsLock"))], Row("CapsLock"))
            .Should().Be("The header template in Work also uses CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_NamesTheFooterWhenOnlyTheFooterUsesTheKey()
    {
        TemplateUseText.TextFor([Footer("Work", Wildcard("CapsLock"))], Row("CapsLock"))
            .Should().Be("The footer template in Work also uses CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_NamesBothTemplatesOfOneProfileWithAPluralVerb()
    {
        TemplateUseText.TextFor([Both("Work", Wildcard("CapsLock"))], Row("CapsLock"))
            .Should().Be("The header and footer templates in Work also use CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_GroupsProfilesThatMatchedTheSameWay()
    {
        TemplateUseText.TextFor(
                [Header("Work", Wildcard("CapsLock")), Header("Games", Wildcard("CapsLock"))], Row("CapsLock"))
            .Should().Be("The header templates in Work and Games also use CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_SpellsOutEachProfileWhenTheyMatchedDifferently()
    {
        TemplateUseText.TextFor(
                [Header("Work", Wildcard("CapsLock")), Footer("Games", Wildcard("CapsLock"))], Row("CapsLock"))
            .Should().Be(
                "The header template in Work and the footer template in Games also use CapsLock. "
                + "Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_NamesAtMostThreeProfilesAndCountsTheRest()
    {
        ProfileTemplateUse[] uses =
        [
            Header("Work", Wildcard("CapsLock")),
            Header("Games", Wildcard("CapsLock")),
            Header("Notes", Wildcard("CapsLock")),
            Header("Mail", Wildcard("CapsLock")),
            Header("Code", Wildcard("CapsLock")),
        ];

        TemplateUseText.TextFor(uses, Row("CapsLock"))
            .Should().Be(
                "The header templates in Work, Games and Notes and 2 more also use CapsLock. "
                + "Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_DoesNotFoldAnUnnamedFooterIntoAHeaderSubject()
    {
        // Three headers and one footer. Naming only the headers and adding "and 1 more" would put
        // the footer under a header subject, so the sentence spells each named Profile out instead.
        ProfileTemplateUse[] uses =
        [
            Header("Work", Wildcard("CapsLock")),
            Header("Games", Wildcard("CapsLock")),
            Header("Notes", Wildcard("CapsLock")),
            Footer("Mail", Wildcard("CapsLock")),
        ];

        TemplateUseText.TextFor(uses, Row("CapsLock"))
            .Should().Be(
                "The header template in Work, the header template in Games, the header template in Notes "
                + "and 1 more also use CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_MatchesIgnoringKeyCase()
    {
        TemplateUseText.TextFor([Header("Work", Wildcard("capslock"))], Row("CapsLock")).Should().NotBeNull();
    }

    [Fact]
    public void TextFor_MatchesAWildcardTemplateHotkeyForARowCarryingExtraModifiers()
    {
        RowCombination row = new("CapsLock", true, false, true, false, "Ctrl+Shift+CapsLock");

        TemplateUseText.TextFor([Header("Work", Wildcard("CapsLock"))], row)
            .Should().Be(
                "The header template in Work also uses Ctrl+Shift+CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_SkipsAPlainTemplateHotkeyWhenTheRowCarriesModifiers()
    {
        // "CapsLock::" fires only when no other modifier is held, so a Ctrl+CapsLock row is
        // untouched by it.
        TemplateHotkey plain = new("CapsLock", false, false, false, false, false);
        RowCombination row = new("CapsLock", true, false, false, false, "Ctrl+CapsLock");

        TemplateUseText.TextFor([Header("Work", plain)], row).Should().BeNull();
    }

    [Fact]
    public void TextFor_MatchesATemplateHotkeyThatCarriesTheSameModifiers()
    {
        // The emitter writes "^!c::" for a Ctrl+Alt+C row, which is the same hotkey name.
        TemplateHotkey ctrlAltC = new("c", false, true, true, false, false);
        RowCombination row = new("c", true, true, false, false, "Ctrl+Alt+C");

        TemplateUseText.TextFor([Header("Work", ctrlAltC)], row)
            .Should().Be("The header template in Work also uses Ctrl+Alt+C. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_SkipsATemplateHotkeyWhoseModifiersTheRowDoesNotCarry()
    {
        TemplateHotkey ctrlAltC = new("c", false, true, true, false, false);
        RowCombination row = new("c", true, false, false, false, "Ctrl+C");

        TemplateUseText.TextFor([Header("Work", ctrlAltC)], row).Should().BeNull();
    }

    [Fact]
    public void TextFor_MatchesAWildcardTemplateHotkeyOnlyWhenTheRowCarriesItsModifiers()
    {
        TemplateHotkey wildcardCtrlC = new("c", true, true, false, false, false);

        TemplateUseText.TextFor(
            [Header("Work", wildcardCtrlC)],
            new RowCombination("c", true, true, false, false, "Ctrl+Alt+C")).Should().NotBeNull();

        TemplateUseText.TextFor(
            [Header("Work", wildcardCtrlC)],
            new RowCombination("c", false, true, false, false, "Alt+C")).Should().BeNull();
    }

    [Fact]
    public void TextFor_MatchesAnAliasTheCallerCanonicalized()
    {
        // The caller canonicalizes both sides, so an accepted alias spelling arrives here as the
        // canonical name and matches a row on the same physical key.
        TemplateUseText.TextFor([Header("Work", Wildcard("LCtrl"))], Row("LCtrl")).Should().NotBeNull();
    }

    [Fact]
    public void TextFor_PromisesNothing()
    {
        string text = TemplateUseText.TextFor([Both("Work", Wildcard("CapsLock"))], Row("CapsLock"))!;

        foreach (string banned in BannedTerms)
            text.Should().NotContainEquivalentOf(banned);
    }
}
