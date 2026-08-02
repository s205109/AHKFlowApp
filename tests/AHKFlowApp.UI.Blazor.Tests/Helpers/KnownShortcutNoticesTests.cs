using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class KnownShortcutNoticesTests
{
    private readonly IHotkeyKeyCatalog _keys = Substitute.For<IHotkeyKeyCatalog>();
    private readonly IKnownShortcutCatalog _knownShortcuts = Substitute.For<IKnownShortcutCatalog>();

    // The Windows use of Win+E, in the shape the client DTOs carry it.
    private static KnownShortcutCatalogDto WinEOnly() =>
        new([
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
        ]);

    // Ctrl+Escape, so the alias test has a row its raw key ("Esc") does not spell.
    private static KnownShortcutCatalogDto CtrlEscapeOnly() =>
        new([
            new KnownShortcutDto("windows.start-menu", "Escape", true, false, false, false,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open the Start menu")],
                null),
        ]);

    private static HotkeyEditModel Row(string key, bool ctrl = false, bool win = false) =>
        new() { Id = Guid.NewGuid(), Description = "Row", Key = key, Ctrl = ctrl, Win = win };

    // The registry hands most keys back unchanged. Tests that need an alias override this.
    private void StubCanonicalizeAsIs() =>
        _keys.CanonicalizeAsync(Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string?>() ?? ""));

    private void StubCatalog(KnownShortcutCatalogDto? catalog) =>
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult(catalog));

    private Task<IReadOnlyDictionary<string, string>> BuildAsync(params HotkeyEditModel[] items) =>
        KnownShortcutNotices.BuildAsync(items, _keys, _knownShortcuts, NullLogger.Instance, CancellationToken.None);

    [Fact]
    public async Task BuildAsync_MatchingRow_KeysTheNoticeByTheComboLabel()
    {
        StubCanonicalizeAsIs();
        StubCatalog(WinEOnly());

        IReadOnlyDictionary<string, string> notices = await BuildAsync(Row("e", win: true));

        notices.Should().ContainKey("Win+E");
        notices["Win+E"].Should().Be(
            "Windows uses Win+E to open File Explorer. Your hotkey may override this shortcut.");
    }

    [Fact]
    public async Task BuildAsync_RowMatchingNothing_IsAbsent()
    {
        StubCanonicalizeAsIs();
        StubCatalog(WinEOnly());

        IReadOnlyDictionary<string, string> notices = await BuildAsync(Row("F13", win: true));

        notices.Should().BeEmpty();
    }

    [Fact]
    public async Task BuildAsync_BlankKey_IsAbsent()
    {
        StubCanonicalizeAsIs();
        StubCatalog(WinEOnly());

        IReadOnlyDictionary<string, string> notices = await BuildAsync(Row("", win: true));

        notices.Should().BeEmpty();
    }

    [Fact]
    public async Task BuildAsync_WhenTheCatalogFetchFails_ReturnsEmpty()
    {
        StubCanonicalizeAsIs();
        StubCatalog(null);

        IReadOnlyDictionary<string, string> notices = await BuildAsync(Row("e", win: true));

        notices.Should().BeEmpty();
    }

    [Fact]
    public async Task BuildAsync_TwoRowsSharingOneCombination_CanonicalizesOnce()
    {
        StubCanonicalizeAsIs();
        StubCatalog(WinEOnly());

        IReadOnlyDictionary<string, string> notices =
            await BuildAsync(Row("e", win: true), Row("e", win: true));

        notices.Should().ContainKey("Win+E");
        await _keys.Received(1).CanonicalizeAsync("e", Arg.Any<CancellationToken>());
    }

    // The one mistake this helper can quietly make. The cell looks up the string it is about to
    // print, which is built from the raw key. Storing the notice under the canonical label
    // ("Ctrl+Escape") would match the catalog and still show no marker.
    [Fact]
    public async Task BuildAsync_AliasKey_KeysTheNoticeByTheRawLabel()
    {
        _keys.CanonicalizeAsync(Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string?>() == "Esc" ? "Escape" : call.Arg<string?>() ?? ""));
        StubCatalog(CtrlEscapeOnly());

        IReadOnlyDictionary<string, string> notices = await BuildAsync(Row("Esc", ctrl: true));

        notices.Should().ContainKey("Ctrl+Esc");
        notices.Should().NotContainKey("Ctrl+Escape");
    }

    // The notice names the keys the owner typed, not the registry's spelling of them — the same
    // rule the edit dialog follows.
    [Fact]
    public async Task BuildAsync_AliasKey_NamesTheRawLabelInTheNotice()
    {
        _keys.CanonicalizeAsync(Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string?>() == "Esc" ? "Escape" : call.Arg<string?>() ?? ""));
        StubCatalog(CtrlEscapeOnly());

        IReadOnlyDictionary<string, string> notices = await BuildAsync(Row("Esc", ctrl: true));

        notices["Ctrl+Esc"].Should().Contain("Ctrl+Esc").And.NotContain("Ctrl+Escape");
    }
}
