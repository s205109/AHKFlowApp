using AHKFlowApp.UI.Blazor.Components.KnownShortcuts;
using AHKFlowApp.UI.Blazor.DTOs;
using Bunit;
using FluentAssertions;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.KnownShortcuts;

public sealed class KnownShortcutSourceChipTests : BunitContext, IAsyncLifetime
{
    public KnownShortcutSourceChipTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static ManagedShortcutUseDto Use(ShortcutRecordOrigin origin, bool ignored) =>
        new("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open a new window",
            origin, OwnerRecordId: null, IsIgnored: ignored);

    [Theory]
    // A silenced use reads "Silenced" whatever it came from — that state is what matters.
    [InlineData(ShortcutRecordOrigin.BuiltIn, true, "Silenced")]
    [InlineData(ShortcutRecordOrigin.Owner, true, "Silenced")]
    [InlineData(ShortcutRecordOrigin.Owner, false, "Yours")]
    [InlineData(ShortcutRecordOrigin.BuiltIn, false, "Built in")]
    public void Chip_SaysWhereTheRowCameFrom(ShortcutRecordOrigin origin, bool ignored, string expected)
    {
        IRenderedComponent<KnownShortcutSourceChip> cut =
            Render<KnownShortcutSourceChip>(p => p.Add(c => c.Use, Use(origin, ignored)));

        cut.Find("[data-test=\"known-shortcut-source-chip\"]").TextContent.Trim()
            .Should().Be(expected);
    }
}
