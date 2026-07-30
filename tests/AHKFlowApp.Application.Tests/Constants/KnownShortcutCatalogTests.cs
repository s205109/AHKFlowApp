using AHKFlowApp.Application.Constants;
using AHKFlowApp.Domain.Enums;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Constants;

public sealed class KnownShortcutCatalogTests
{
    [Fact]
    public void All_HasExpectedRecordCount()
    {
        // 67 Windows rows plus 36 browser rows, per design §3.
        KnownShortcutCatalog.All.Should().HaveCount(103);
    }

    [Fact]
    public void All_RowIdsUseAKnownPrefix()
    {
        // Two sources ship today. A third one gets its own prefix and its own line here, so a
        // typo in an id cannot quietly create a source nothing else knows about.
        KnownShortcutCatalog.All.Should().OnlyContain(s =>
            s.Id.StartsWith("windows.", StringComparison.Ordinal) ||
            s.Id.StartsWith("browser.", StringComparison.Ordinal));
    }

    [Fact]
    public void All_IdsAreUnique()
    {
        KnownShortcutCatalog.All.Select(s => s.Id)
            .Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void All_CombinationsAreUnique()
    {
        // Grouping rule: one record per combination, with Uses carrying every label.
        KnownShortcutCatalog.All
            .Select(s => (s.Key.ToUpperInvariant(), s.Ctrl, s.Alt, s.Shift, s.Win))
            .Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void All_KeysAreExpressibleHotkeyKeys()
    {
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
            HotkeyKeys.IsValidHotkeyKey(shortcut.Key)
                .Should().BeTrue($"{shortcut.Id} uses key '{shortcut.Key}'");
    }

    [Fact]
    public void All_KeysAreStoredCanonically()
    {
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
        {
            HotkeyKeys.TryCanonicalize(shortcut.Key, out string canonical);
            shortcut.Key.Should().Be(canonical, $"{shortcut.Id} must store the canonical spelling");
        }
    }

    [Fact]
    public void All_EveryShortcutHasAtLeastOneUse()
    {
        KnownShortcutCatalog.All.Should().OnlyContain(s => s.Uses.Count > 0);
    }

    [Fact]
    public void All_EveryUseHasPinnedEvidence()
    {
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
            foreach (ShortcutUse use in shortcut.Uses)
            {
                use.EvidenceUrl.Should().StartWith("https://", $"{shortcut.Id} / {use.UsedBy}");
                use.EvidenceCheckedOn.Should().BeOnOrAfter(new DateOnly(2026, 7, 29));
            }
    }

    [Fact]
    public void All_EveryUseHasADoesPhrase()
    {
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
            foreach (ShortcutUse use in shortcut.Uses)
            {
                use.Does.Should().NotBeNullOrWhiteSpace($"{shortcut.Id} / {use.UsedBy}");
                char.IsLower(use.Does[0]).Should()
                    .BeTrue($"{shortcut.Id} / {use.UsedBy} must read as a lowercase verb phrase");
            }
    }

    [Fact]
    public void All_DoesPhrasesUsePlainEnglish()
    {
        // Each phrase lands in a sentence a reader has to understand at a glance, so the manifest
        // holds itself to AGENTS.md's Plain English rules. "toggle" is the one word that kept
        // creeping in; "turn X on and off" says the same thing in common words. A phrase also
        // reads as a whole sentence with "Windows uses Win+E to …" in front of it, which is why
        // it must not start with "to".
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
            foreach (ShortcutUse use in shortcut.Uses)
            {
                use.Does.Should().NotStartWith("toggle", $"{shortcut.Id} / {use.UsedBy}");
                use.Does.Should().NotStartWith("to ", $"{shortcut.Id} / {use.UsedBy}");
                use.Does.Should().NotEndWith(".", $"{shortcut.Id} / {use.UsedBy}");
            }
    }

    [Fact]
    public void Protected_IsClaimedByExactlyTheTwoDocumentedRows()
    {
        KnownShortcutCatalog.All
            .Where(s => s.Uses.Any(u => u.Protection == ShortcutProtection.Protected))
            .Select(s => s.Id)
            .Should().BeEquivalentTo(["windows.secure-attention", "windows.lock"]);
    }

    [Fact]
    public void Protected_RowsCiteMicrosoft()
    {
        foreach (ShortcutUse use in KnownShortcutCatalog.All
                     .SelectMany(s => s.Uses)
                     .Where(u => u.Protection == ShortcutProtection.Protected))
            use.EvidenceUrl.Should().Contain("microsoft.com");
    }

    [Fact]
    public void Windows_RowsAreAllGlobal()
    {
        KnownShortcutCatalog.All
            .Where(s => s.Id.StartsWith("windows.", StringComparison.Ordinal))
            .SelectMany(s => s.Uses)
            .Should().OnlyContain(u => u.Scope == ShortcutScope.Global);
    }

    [Fact]
    public void Browser_RowsAreForegroundNormalAndNameBothBrowsers()
    {
        KnownShortcut[] browserRows =
        [
            .. KnownShortcutCatalog.All.Where(s => s.Id.StartsWith("browser.", StringComparison.Ordinal))
        ];

        browserRows.Should().HaveCount(36);

        foreach (KnownShortcut shortcut in browserRows)
        {
            shortcut.Uses.Select(u => u.UsedBy).Should()
                .BeEquivalentTo(["Chrome", "Edge"], $"{shortcut.Id} is documented by both");
            shortcut.Uses.Should().OnlyContain(u => u.Scope == ShortcutScope.Foreground);
            shortcut.Uses.Should().OnlyContain(u => u.Protection == ShortcutProtection.Normal);
        }
    }

    [Fact]
    public void Browser_EachUseCitesItsOwnBrowsersPage()
    {
        // One evidence page per use is the manifest rule. Both uses pointing at one page would
        // mean one of the two claims is unproven.
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All
                     .Where(s => s.Id.StartsWith("browser.", StringComparison.Ordinal)))
        {
            shortcut.Uses.Single(u => u.UsedBy == "Chrome").EvidenceUrl.Should().Contain("google.com");
            shortcut.Uses.Single(u => u.UsedBy == "Edge").EvidenceUrl.Should().Contain("microsoft.com");
        }
    }

    [Fact]
    public void FirefoxIsNotYetClaimed()
    {
        // Design §3: Mozilla's page was not enumerated, so no row may name Firefox.
        KnownShortcutCatalog.All.SelectMany(s => s.Uses)
            .Should().NotContain(u => u.UsedBy == "Firefox");
    }

    [Fact]
    public void Manifest_TextMakesNoAbsoluteClaim()
    {
        // One rule, shared with the owner-input validator through ShortcutWording. Two copies
        // would let the manifest ban a term the validator still accepts.
        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
        {
            if (shortcut.WarningText is string text)
                ShortcutWording.MakesAbsoluteClaim(text).Should().BeFalse(shortcut.Id);

            foreach (ShortcutUse use in shortcut.Uses)
                ShortcutWording.MakesAbsoluteClaim(use.Does).Should()
                    .BeFalse($"{shortcut.Id} / {use.UsedBy}");
        }
    }
}
