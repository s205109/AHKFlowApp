using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class TemplateUseTextTests
{
    // The notice must never promise an outcome. CONTEXT.md:99 rules that out, and the AutoHotkey
    // docs say "eclipsed" without promising it in every case.
    private static readonly string[] BannedTerms = ["never", "will not", "cannot", "won't", "can't"];

    private static ProfileTemplateUse Header(string profile, params string[] keys) =>
        new(profile, keys, []);

    private static ProfileTemplateUse Footer(string profile, params string[] keys) =>
        new(profile, [], keys);

    private static ProfileTemplateUse Both(string profile, string key) =>
        new(profile, [key], [key]);

    [Fact]
    public void TextFor_ReturnsNullWhenNoTemplateUsesTheKey()
    {
        TemplateUseText.TextFor([Header("Work", "ScrollLock")], "CapsLock").Should().BeNull();
    }

    [Fact]
    public void TextFor_ReturnsNullWhenTheRowHasNoKey()
    {
        TemplateUseText.TextFor([Header("Work", "CapsLock")], "").Should().BeNull();
    }

    [Fact]
    public void TextFor_NamesOneProfileAndItsHeader()
    {
        TemplateUseText.TextFor([Header("Work", "CapsLock")], "CapsLock")
            .Should().Be("The header template in Work also uses CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_NamesTheFooterWhenOnlyTheFooterUsesTheKey()
    {
        TemplateUseText.TextFor([Footer("Work", "CapsLock")], "CapsLock")
            .Should().Be("The footer template in Work also uses CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_NamesBothTemplatesOfOneProfileWithAPluralVerb()
    {
        TemplateUseText.TextFor([Both("Work", "CapsLock")], "CapsLock")
            .Should().Be("The header and footer templates in Work also use CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_GroupsProfilesThatMatchedTheSameWay()
    {
        TemplateUseText.TextFor([Header("Work", "CapsLock"), Header("Games", "CapsLock")], "CapsLock")
            .Should().Be("The header templates in Work and Games also use CapsLock. Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_SpellsOutEachProfileWhenTheyMatchedDifferently()
    {
        TemplateUseText.TextFor([Header("Work", "CapsLock"), Footer("Games", "CapsLock")], "CapsLock")
            .Should().Be(
                "The header template in Work and the footer template in Games also use CapsLock. "
                + "Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_NamesAtMostThreeProfilesAndCountsTheRest()
    {
        ProfileTemplateUse[] uses =
        [
            Header("Work", "CapsLock"),
            Header("Games", "CapsLock"),
            Header("Notes", "CapsLock"),
            Header("Mail", "CapsLock"),
            Header("Code", "CapsLock"),
        ];

        TemplateUseText.TextFor(uses, "CapsLock")
            .Should().Be(
                "The header templates in Work, Games and Notes and 2 more also use CapsLock. "
                + "Your hotkey may not fire.");
    }

    [Fact]
    public void TextFor_MatchesIgnoringKeyCase()
    {
        TemplateUseText.TextFor([Header("Work", "capslock")], "CapsLock").Should().NotBeNull();
    }

    [Fact]
    public void TextFor_PromisesNothing()
    {
        string text = TemplateUseText.TextFor([Both("Work", "CapsLock")], "CapsLock")!;

        foreach (string banned in BannedTerms)
            text.Should().NotContainEquivalentOf(banned);
    }
}
