using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class KnownShortcutWarningTests
{
    private static readonly string[] BannedTerms = ["never", "will not", "cannot", "won't", "can't"];

    private static KnownShortcutDto Shortcut(string id, string key, bool ctrl, bool alt, bool shift, bool win,
        params ShortcutUseDto[] uses) =>
        new(id, key, ctrl, alt, shift, win, uses, null);

    private static ShortcutUseDto Use(string usedBy, ShortcutProtection protection, ShortcutScope scope, string does) =>
        new(usedBy, protection, scope, does);

    [Fact]
    public void Match_FindsCombinationIgnoringKeyCase()
    {
        KnownShortcutCatalogDto catalog = new([
            Shortcut("windows.file-explorer", "e", false, false, false, true,
                Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")),
        ]);

        KnownShortcutWarning.Match(catalog, "E", ctrl: false, alt: false, shift: false, win: true)
            .Should().NotBeNull();
    }

    [Fact]
    public void Match_RequiresEveryModifierToAgree()
    {
        KnownShortcutCatalogDto catalog = new([
            Shortcut("windows.file-explorer", "e", false, false, false, true,
                Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")),
        ]);

        KnownShortcutWarning.Match(catalog, "e", ctrl: true, alt: false, shift: false, win: true)
            .Should().BeNull();
    }

    [Fact]
    public void Match_OnNullCatalog_ReturnsNull()
    {
        KnownShortcutWarning.Match(null, "e", false, false, false, true).Should().BeNull();
    }

    [Fact]
    public void TextFor_SingleGlobalUse_NamesUserAndAction()
    {
        KnownShortcutDto shortcut = Shortcut("windows.file-explorer", "e", false, false, false, true,
            Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer"));

        KnownShortcutWarning.TextFor(shortcut, "Win+E").Should().Be(
            "Windows uses Win+E to open File Explorer. " +
            "Your hotkey may override this shortcut.");
    }

    // The next three build their DTOs by hand and never read the manifest. That is deliberate:
    // no shipped row is Foreground or carries two uses until Stage 2, so this is the only thing
    // holding the grouping and the Foreground tail correct in the meantime. The browser.* ids are
    // just labels here — nothing looks them up.
    [Fact]
    public void TextFor_TwoLabelsSharingOneAction_JoinsThemAndUsesPluralVerb()
    {
        KnownShortcutDto shortcut = Shortcut("browser.new-tab", "t", true, false, false, false,
            Use("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new tab"),
            Use("Edge", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new tab"));

        KnownShortcutWarning.TextFor(shortcut, "Ctrl+T").Should().StartWith(
            "Chrome and Edge use Ctrl+T to open a new tab, but only while that application is in front.");
    }

    [Fact]
    public void TextFor_ThreeLabels_UsesCommaThenAnd()
    {
        KnownShortcutDto shortcut = Shortcut("browser.find", "f", true, false, false, false,
            Use("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "find text on the page"),
            Use("Edge", ShortcutProtection.Normal, ShortcutScope.Foreground, "find text on the page"),
            Use("Firefox", ShortcutProtection.Normal, ShortcutScope.Foreground, "find text on the page"));

        KnownShortcutWarning.TextFor(shortcut, "Ctrl+F")
            .Should().StartWith("Chrome, Edge and Firefox use Ctrl+F to find text on the page,");
    }

    [Fact]
    public void TextFor_DifferentActions_ProduceOneSentenceEach()
    {
        KnownShortcutDto shortcut = Shortcut("windows.file-explorer", "e", false, false, false, true,
            Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer"),
            Use("Visual Studio", ShortcutProtection.Unknown, ShortcutScope.Foreground, "open the error list"));

        string text = KnownShortcutWarning.TextFor(shortcut, "Win+E");

        text.Should().Contain("Windows uses Win+E to open File Explorer.");
        text.Should().Contain(
            "Visual Studio uses Win+E to open the error list, but only while that application is in front.");
    }

    [Fact]
    public void TextFor_StrongestProtectionWinsTheClosingSentence()
    {
        KnownShortcutDto shortcut = Shortcut("windows.lock", "l", false, false, false, true,
            Use("Windows", ShortcutProtection.Protected, ShortcutScope.Global, "lock the computer"),
            Use("My tool", ShortcutProtection.Unknown, ShortcutScope.Global, "log the time"));

        KnownShortcutWarning.TextFor(shortcut, "Win+L")
            .Should().EndWith("Windows handles these keys itself.");
    }

    [Fact]
    public void TextFor_UnknownOnly_UsesTheNeutralClosingSentence()
    {
        KnownShortcutDto shortcut = Shortcut("owner.thing", "q", true, true, false, false,
            Use("My tool", ShortcutProtection.Unknown, ShortcutScope.Global, "do something"));

        KnownShortcutWarning.TextFor(shortcut, "Ctrl+Alt+Q")
            .Should().EndWith("What happens when you press these keys depends on what else is installed.");
    }

    [Fact]
    public void TextFor_OverrideText_IsReturnedVerbatim()
    {
        KnownShortcutDto shortcut = new("windows.odd", "q", false, false, false, true,
            [Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "do something odd")],
            "Hand-written text for this row.");

        KnownShortcutWarning.TextFor(shortcut, "Win+Q").Should().Be("Hand-written text for this row.");
    }

    [Theory]
    [InlineData(ShortcutProtection.Protected, ShortcutScope.Global)]
    [InlineData(ShortcutProtection.Normal, ShortcutScope.Global)]
    [InlineData(ShortcutProtection.Normal, ShortcutScope.Foreground)]
    [InlineData(ShortcutProtection.Unknown, ShortcutScope.Global)]
    [InlineData(ShortcutProtection.Unknown, ShortcutScope.Foreground)]
    public void TextFor_MakesNoAbsoluteClaim(ShortcutProtection protection, ShortcutScope scope)
    {
        KnownShortcutDto shortcut = Shortcut("any.row", "e", false, false, false, true,
            Use("Windows", protection, scope, "do something"));

        string text = KnownShortcutWarning.TextFor(shortcut, "Win+E");

        foreach (string banned in BannedTerms)
            text.Should().NotContainEquivalentOf(banned, $"'{banned}' promises an outcome we cannot know");
    }
}
