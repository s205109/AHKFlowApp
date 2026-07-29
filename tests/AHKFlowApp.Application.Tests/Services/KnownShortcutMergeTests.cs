using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class KnownShortcutMergeTests
{
    private static readonly Guid Owner = Guid.NewGuid();

    // The manifest count is read, never hard-coded: a catalog change must not break this file.
    private static int ManifestCount => KnownShortcutCatalog.All.Count;

    [Fact]
    public void ForDialog_WithNoOverlay_ReturnsTheWholeManifest()
    {
        IReadOnlyList<KnownShortcutDto> merged = KnownShortcutMerge.ForDialog([], []);

        merged.Should().HaveCount(ManifestCount);
    }

    [Fact]
    public void ForDialog_OwnerRecordOnABuiltInCombination_AddsAUse()
    {
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner)
            .WithCombination("E", win: true)
            .UsedBy("My notes tool")
            .Does("open my notes")
            .Build();

        KnownShortcutDto merged = KnownShortcutMerge.ForDialog([owned], [])
            .Single(s => s.Id == "windows.file-explorer");

        merged.Uses.Select(u => u.UsedBy).Should().BeEquivalentTo(["Windows", "My notes tool"]);
    }

    [Fact]
    public void ForDialog_OwnerRecordOnAProtectedCombination_CannotWeakenIt()
    {
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner)
            .WithCombination("L", win: true)
            .UsedBy("My tool")
            .WithProtection(ShortcutProtection.Unknown)
            .Build();

        KnownShortcutDto merged = KnownShortcutMerge.ForDialog([owned], [])
            .Single(s => s.Id == "windows.lock");

        merged.Uses.Should().Contain(u => u.Protection == ShortcutProtection.Protected);
    }

    [Fact]
    public void ForDialog_IgnoringOneUse_LeavesTheOtherUsesWarning()
    {
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner).WithCombination("E", win: true).UsedBy("My notes tool").Build();
        IgnoredKnownShortcut ignore = new IgnoredKnownShortcutBuilder()
            .ForOwner(Owner).ForShortcut("windows.file-explorer").UsedBy("Windows").Build();

        KnownShortcutDto merged = KnownShortcutMerge.ForDialog([owned], [ignore])
            .Single(s => s.Id == "windows.file-explorer");

        merged.Uses.Select(u => u.UsedBy).Should().BeEquivalentTo(["My notes tool"]);
    }

    [Fact]
    public void ForDialog_IgnoringOneBrowserUse_LeavesTheOtherBrowser()
    {
        // A browser combination has a Chrome use and an Edge use, silenced separately.
        IgnoredKnownShortcut ignore = new IgnoredKnownShortcutBuilder()
            .ForOwner(Owner).ForShortcut("browser.new-window").UsedBy("Chrome").Build();

        KnownShortcutDto merged = KnownShortcutMerge.ForDialog([], [ignore])
            .Single(s => s.Id == "browser.new-window");

        merged.Uses.Select(u => u.UsedBy).Should().BeEquivalentTo(["Edge"]);
    }

    [Fact]
    public void ForDialog_IgnoringEveryUse_DropsTheShortcutEntirely()
    {
        IgnoredKnownShortcut ignore = new IgnoredKnownShortcutBuilder()
            .ForOwner(Owner).ForShortcut("windows.file-explorer").UsedBy("Windows").Build();

        KnownShortcutMerge.ForDialog([], [ignore])
            .Should().NotContain(s => s.Id == "windows.file-explorer");
    }

    [Fact]
    public void ForDialog_IgnoreNamingAnUnknownId_IsSkipped()
    {
        IgnoredKnownShortcut ignore = new IgnoredKnownShortcutBuilder()
            .ForOwner(Owner).ForShortcut("windows.retired-in-a-later-release").UsedBy("Windows").Build();

        Action act = () => KnownShortcutMerge.ForDialog([], [ignore]);

        act.Should().NotThrow();
        KnownShortcutMerge.ForDialog([], [ignore]).Should().HaveCount(ManifestCount);
    }

    [Fact]
    public void ForDialog_OwnerRecordSpellsTheKeyDifferently_StillMatchesTheBuiltIn()
    {
        // "Esc" canonicalizes to "Escape", so this must land on the existing Win+Escape row.
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner).WithCombination("Esc", win: true).UsedBy("My tool").Build();

        KnownShortcutMerge.ForDialog([owned], [])
            .Should().HaveCount(ManifestCount, "an alias spelling must not create a second row");
    }

    [Fact]
    public void ForDialog_OwnerRecordOnANewCombination_AddsAShortcut()
    {
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner).WithCombination("F7", ctrl: true, alt: true).UsedBy("My tool").Build();

        KnownShortcutMerge.ForDialog([owned], []).Should().HaveCount(ManifestCount + 1);
    }

    [Fact]
    public void ForManagement_ReturnsIgnoredUsesSoTheyCanBeRestored()
    {
        IgnoredKnownShortcut ignore = new IgnoredKnownShortcutBuilder()
            .ForOwner(Owner).ForShortcut("windows.file-explorer").UsedBy("Windows").Build();

        ManagedShortcutUseDto use = KnownShortcutMerge.ForManagement([], [ignore])
            .Single(s => s.Id == "windows.file-explorer").Uses.Single();

        use.IsIgnored.Should().BeTrue();
        use.Origin.Should().Be(ShortcutRecordOrigin.BuiltIn);
        use.OwnerRecordId.Should().BeNull();
    }

    [Fact]
    public void ForManagement_OwnerUseCarriesItsRecordIdSoItCanBeDeleted()
    {
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner).WithCombination("F7", ctrl: true).UsedBy("My tool").Build();

        ManagedShortcutUseDto use = KnownShortcutMerge.ForManagement([owned], [])
            .Single(s => s.Uses.Any(u => u.UsedBy == "My tool")).Uses.Single();

        use.Origin.Should().Be(ShortcutRecordOrigin.Owner);
        use.OwnerRecordId.Should().Be(owned.Id);
        use.IsIgnored.Should().BeFalse();
    }

    [Fact]
    public void ForManagement_KeepsCanonicalCasing_ForNamedKeys()
    {
        IReadOnlyList<ManagedKnownShortcutDto> merged = KnownShortcutMerge.ForManagement([], []);

        merged.Single(s => s.Id == "windows.close-magnifier").Key.Should().Be("Escape");
        merged.Single(s => s.Id == "windows.file-explorer").Key.Should().Be("e");
    }

    [Fact]
    public void ForDialog_KeepsCanonicalCasing_ForNamedKeys()
    {
        IReadOnlyList<KnownShortcutDto> merged = KnownShortcutMerge.ForDialog([], []);

        merged.Single(s => s.Id == "windows.close-magnifier").Key.Should().Be("Escape");
        merged.Single(s => s.Id == "windows.file-explorer").Key.Should().Be("e");
    }

    [Fact]
    public void ForDialog_CarriesWarningText_FromTheBuiltInRow()
    {
        // No shipped row sets WarningText, so the built-in list is hand-built here. Without this
        // the dialog path could drop the override and no test would notice.
        KnownShortcut[] builtIns =
        [
            new("test.row", "F7", Ctrl: true, Alt: false, Shift: false, Win: false,
                [
                    new ShortcutUse("Test app", ShortcutProtection.Normal, ShortcutScope.Foreground,
                        "do the thing", "https://example.test/evidence", new DateOnly(2026, 7, 29)),
                ],
                "Hand-written text for this row."),
        ];

        KnownShortcutMerge.ForDialog(builtIns, [], []).Single().WarningText
            .Should().Be("Hand-written text for this row.");
    }

    [Fact]
    public void ForManagement_GroupsCaseVariants_IntoOneRow()
    {
        // The built-in row stores "e"; the owner typed "E". One row, two uses.
        CustomKnownShortcut owned = new CustomKnownShortcutBuilder()
            .ForOwner(Owner).WithCombination("E", win: true).UsedBy("My tool").Build();

        IReadOnlyList<ManagedKnownShortcutDto> merged = KnownShortcutMerge.ForManagement([owned], []);

        merged.Should().HaveCount(ManifestCount);
        merged.Single(s => s.Id == "windows.file-explorer").Uses.Should().HaveCount(2);
    }
}
