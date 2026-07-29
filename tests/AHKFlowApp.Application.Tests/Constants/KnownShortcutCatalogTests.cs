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
        // 67 Windows rows, per design §3. The 36 browser rows are Stage 2 — when they land,
        // this becomes 103. Recount from the manifest then; do not guess a new number.
        KnownShortcutCatalog.All.Should().HaveCount(67);
    }

    [Fact]
    public void All_ContainsOnlyWindowsRows()
    {
        // Guards the stage boundary. A browser row appearing here means Stage 2 work leaked in
        // without the ignore mechanism that makes it tolerable.
        KnownShortcutCatalog.All.Should()
            .OnlyContain(s => s.Id.StartsWith("windows.", StringComparison.Ordinal));
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
    public void All_RowsCarryExactlyOneUse()
    {
        // True only while the manifest is Windows-only. Stage 2's browser rows carry two uses
        // each, so that plan replaces this test rather than adding rows around it.
        KnownShortcutCatalog.All.Should().OnlyContain(s => s.Uses.Count == 1);
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
        string[] banned = ["never", "will not", "cannot", "won't", "can't"];

        foreach (KnownShortcut shortcut in KnownShortcutCatalog.All)
        {
            foreach (string term in banned)
            {
                shortcut.WarningText?.ToLowerInvariant().Should().NotContain(term);
                foreach (ShortcutUse use in shortcut.Uses)
                    use.Does.ToLowerInvariant().Should().NotContain(term, $"{shortcut.Id} / {use.UsedBy}");
            }
        }
    }
}
