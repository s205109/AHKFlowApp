using AHKFlowApp.TestUtilities.Fixtures;
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
            "Chrome and Edge use Ctrl+T to open a new tab, but only while those applications are in front.");
    }

    [Fact]
    public void TextFor_ForegroundTail_AgreesWithTheNumberOfLabels()
    {
        // One label keeps the singular tail. Two share one sentence, so the tail turns plural —
        // "Chrome and Edge use … while that application is in front" disagreed with itself.
        KnownShortcutDto one = Shortcut("browser.new-tab", "t", true, false, false, false,
            Use("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new tab"));

        KnownShortcutDto two = Shortcut("browser.new-tab", "t", true, false, false, false,
            Use("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new tab"),
            Use("Edge", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new tab"));

        KnownShortcutWarning.TextFor(one, "Ctrl+T")
            .Should().Contain("but only while that application is in front.")
            .And.NotContain("those applications");

        KnownShortcutWarning.TextFor(two, "Ctrl+T")
            .Should().Contain("but only while those applications are in front.")
            .And.NotContain("that application");
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
    public void TextFor_ProtectedBeatsNormal_ForTheClosingSentence()
    {
        // The pairing Stage 2's merged uses produce most often: a curated Windows row plus an
        // owner-recorded Normal use on the same combination. Without this, Normal taking
        // precedence over Protected would go unnoticed.
        KnownShortcutDto shortcut = Shortcut("windows.lock", "l", false, false, false, true,
            Use("Windows", ShortcutProtection.Protected, ShortcutScope.Global, "lock the computer"),
            Use("My tool", ShortcutProtection.Normal, ShortcutScope.Global, "log the time"));

        KnownShortcutWarning.TextFor(shortcut, "Win+L")
            .Should().EndWith("Windows handles these keys itself.");
    }

    [Fact]
    public void TextFor_NormalBeatsUnknown_ForTheClosingSentence()
    {
        KnownShortcutDto shortcut = Shortcut("windows.file-explorer", "e", false, false, false, true,
            Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer"),
            Use("My tool", ShortcutProtection.Unknown, ShortcutScope.Global, "log the time"));

        KnownShortcutWarning.TextFor(shortcut, "Win+E")
            .Should().EndWith("Your hotkey may override this shortcut.");
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

    [Fact]
    public void DestinationTextFor_ModifierDestination_SaysShortcutsMayAlsoRespond()
    {
        KnownShortcutCatalogDto catalog = new([]);

        KnownShortcutWarning.DestinationTextFor(catalog, "Ctrl", "CapsLock")
            .Should().Be(
                "This hotkey makes CapsLock act as Ctrl. " +
                "Shortcuts that use Ctrl may also respond when you hold CapsLock.");
    }

    [Theory]
    [InlineData("LCtrl", "Ctrl")]
    [InlineData("RCtrl", "Ctrl")]
    [InlineData("Alt", "Alt")]
    [InlineData("LAlt", "Alt")]
    [InlineData("RAlt", "Alt")]
    [InlineData("Shift", "Shift")]
    [InlineData("LShift", "Shift")]
    [InlineData("RShift", "Shift")]
    [InlineData("LWin", "the Windows key")]
    [InlineData("RWin", "the Windows key")]
    public void DestinationTextFor_EverySideOfAModifier_ReadsAsThePlainModifier(string destination, string label)
    {
        KnownShortcutCatalogDto catalog = new([]);

        KnownShortcutWarning.DestinationTextFor(catalog, destination, "CapsLock")
            .Should().Contain($"Shortcuts that use {label} may also respond when you hold CapsLock.");
    }

    [Fact]
    public void DestinationTextFor_MatchesTheCatalogWithNoModifiers_EvenWhenTheRowHasThem()
    {
        // ^c::F12 sends a bare F12: AHK releases a modifier that is on the source and not on the
        // destination. So the F12 row must match even though the row itself carries Ctrl.
        KnownShortcutCatalogDto catalog = new([
            Shortcut("browser.devtools-f12", "F12", false, false, false, false,
                Use("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open developer tools")),
        ]);

        KnownShortcutWarning.DestinationTextFor(catalog, "F12", "Ctrl+C")
            .Should().Be(
                "This hotkey makes Ctrl+C act as F12. " +
                "Chrome uses F12 to open developer tools, but only while that application is in front.");
    }

    [Fact]
    public void DestinationTextFor_NeverAddsTheOverrideClosing()
    {
        KnownShortcutCatalogDto catalog = new([
            Shortcut("browser.devtools-f12", "F12", false, false, false, false,
                Use("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open developer tools")),
        ]);

        string? text = KnownShortcutWarning.DestinationTextFor(catalog, "F12", "CapsLock");

        text.Should().NotContain("override");
        foreach (string banned in BannedTerms)
            text.Should().NotContainEquivalentOf(banned);
    }

    [Fact]
    public void DestinationTextFor_ProtectedDestination_SaysWindowsHandlesTheKeys()
    {
        KnownShortcutCatalogDto catalog = new([
            Shortcut("windows.print-screen", "PrintScreen", false, false, false, false,
                Use("Windows", ShortcutProtection.Protected, ShortcutScope.Global, "take a screenshot")),
        ]);

        KnownShortcutWarning.DestinationTextFor(catalog, "PrintScreen", "F1")
            .Should().EndWith("Windows handles these keys itself.");
    }

    [Fact]
    public void DestinationTextFor_ModifierThatIsAlsoACatalogRow_SaysBoth()
    {
        // An owner can record a use of bare Ctrl: CreateCustomKnownShortcutCommand accepts any
        // valid hotkey key, and modifier keys are valid ones.
        KnownShortcutCatalogDto catalog = new([
            Shortcut("owner.ctrl", "Ctrl", false, false, false, false,
                Use("My macro tool", ShortcutProtection.Normal, ShortcutScope.Global, "cancel a recording")),
        ]);

        string? text = KnownShortcutWarning.DestinationTextFor(catalog, "Ctrl", "CapsLock");

        text.Should().Contain("My macro tool uses Ctrl to cancel a recording.");
        text.Should().Contain("Shortcuts that use Ctrl may also respond when you hold CapsLock.");
    }

    [Fact]
    public void DestinationTextFor_OrdinaryKeyNothingUses_SaysNothing()
    {
        KnownShortcutCatalogDto catalog = new([
            Shortcut("windows.file-explorer", "e", false, false, false, true,
                Use("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")),
        ]);

        KnownShortcutWarning.DestinationTextFor(catalog, "F13", "CapsLock").Should().BeNull();
    }

    [Fact]
    public void DestinationTextFor_NoDestination_SaysNothing()
    {
        KnownShortcutCatalogDto catalog = new([]);

        KnownShortcutWarning.DestinationTextFor(catalog, null, "CapsLock").Should().BeNull();
        KnownShortcutWarning.DestinationTextFor(catalog, "   ", "CapsLock").Should().BeNull();
    }

    [Fact]
    public void DestinationTextFor_NoCatalog_StillWarnsAboutAModifier()
    {
        // The list failing to load must not hide the modifier rule, which needs no catalog.
        KnownShortcutWarning.DestinationTextFor(null, "Ctrl", "CapsLock")
            .Should().Contain("Shortcuts that use Ctrl may also respond");
    }

    public static TheoryData<string> RegistryModifiers()
    {
        TheoryData<string> data = [];
        foreach (string canonical in HotkeyKeyFixtures.ModifierCanonicals)
            data.Add(canonical);

        return data;
    }

    // Guards the hard-coded modifier label map against the key registry it mirrors. A modifier
    // added to HotkeyKeys with no label entry produces no notice at all, and nothing else catches
    // it. One case per key, so the failing test name already names the missing modifier.
    [Theory]
    [MemberData(nameof(RegistryModifiers))]
    public void DestinationTextFor_EveryRegistryModifier_WarnsAboutTheModifier(string canonical)
    {
        // A null catalog isolates the modifier branch: Match returns null, so any text produced
        // here came from the label map.
        string? text = KnownShortcutWarning.DestinationTextFor(catalog: null, canonical, "Ctrl+F1");

        text.Should().NotBeNull(
            $"'{canonical}' is a modifier in HotkeyKeys but has no entry in "
            + "KnownShortcutWarning.s_modifierLabels — add it there");
        text.Should().Contain("may also respond");
    }
}
