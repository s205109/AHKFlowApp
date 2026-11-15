using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.Components.Hotkeys;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using AngleSharp.Html.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotkeys;

public abstract class HotkeyEditDialogTestsBase : BunitContext, IAsyncLifetime
{
    protected static readonly HotkeyKeyDto[] CatalogKeys =
    [
        new("F1", "Function keys", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("c", "Letters & digits", ["HotkeyKey", "RemapDest", "SendToken"], false),
        new("Volume_Up", "Media & browser", ["SendToken"], true),
        new("Up", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("Down", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("Left", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
        new("Right", "Navigation & editing", ["HotkeyKey", "RemapDest", "SendToken"], true),
    ];

    protected readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    protected readonly IHotkeyKeyCatalog _catalog = Substitute.For<IHotkeyKeyCatalog>();
    protected readonly IKnownShortcutCatalog _knownShortcuts = Substitute.For<IKnownShortcutCatalog>();

    protected static KnownShortcutCatalogDto WinECatalog() =>
        new([
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
        ]);

    // Win+E plus a bare F12 row. The F12 row is what a remap destination matches: a destination is
    // looked up with no modifiers at all.
    protected static KnownShortcutCatalogDto WinEAndF12Catalog() =>
        new([
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
            new KnownShortcutDto("browser.devtools-f12", "F12", false, false, false, false,
                [new ShortcutUseDto("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, "open developer tools")],
                null),
        ]);

    protected HotkeyEditDialogTestsBase()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());

        // Mirrors the real catalog: role filtering for the pickers, and the bracing rule the
        // SendKeys panel composes tokens with.
        _catalog.ForRoleAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult<IReadOnlyList<HotkeyKeyDto>>(
                [.. CatalogKeys.Where(k => k.Roles.Contains(call.Arg<string>()))]));
        _catalog.GroupOf(Arg.Any<string>())
            .Returns(call => CatalogKeys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.Group);
        _catalog.RequiresBracesInSend(Arg.Any<string>())
            .Returns(call => CatalogKeys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.RequiresBracesInSend ?? false);
        // Canonicalization is a real code path now: without this the substitute returns null and
        // every combination misses its catalog row.
        _catalog.CanonicalizeAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string>() ?? ""));
        Services.AddSingleton(_catalog);

        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(WinECatalog()));
        Services.AddSingleton(_knownShortcuts);

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    // Dialogs render only inside MudDialogProvider; every test needs the same three lines, so
    // they live here rather than being copied per test.
    protected async Task<IRenderedComponent<MudDialogProvider>> ShowDialogAsync(HotkeyEditModel? item = null)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };
            if (item is not null)
                parameters[nameof(HotkeyEditDialog.Item)] = item;

            await dialogService.ShowAsync<HotkeyEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    // The key is a KeyPicker, not a plain text field: driving its ValueChanged is what a
    // selection from the dropdown does, without depending on popover/JS behaviour.
    protected static bool IsChecked(IRenderedComponent<MudDialogProvider> provider, string dataTest) =>
        ((IHtmlInputElement)provider.Find($"input[data-test=\"{dataTest}\"]")).IsChecked;

    // Same idea for the modifier boxes: drive ValueChanged rather than the rendered input, so the
    // test does not depend on MudCheckBox's internal markup.
    protected static Task SetModifierAsync(IRenderedComponent<MudDialogProvider> provider, string dataTest, bool value) =>
        provider.InvokeAsync(() => provider
            .FindComponents<MudCheckBox<bool>>()
            .Single(c => c.Instance.UserAttributes.TryGetValue("data-test", out object? v) && (string?)v == dataTest)
            .Instance.ValueChanged.InvokeAsync(value));

    protected static Task SetKeyAsync(IRenderedComponent<MudDialogProvider> provider, string dataTest, string? key) =>
        provider.InvokeAsync(() => provider
            .FindComponents<KeyPicker>()
            .Single(p => p.Instance.DataTest == dataTest)
            .Instance.ValueChanged.InvokeAsync(key));

    /// <summary>The preview run in flight right now. Capture it while its generation is still
    /// current, then await it later to know that generation's response has been handled.</summary>
    protected static Task PreviewRun(IRenderedComponent<MudDialogProvider> provider) =>
        provider.FindComponent<HotkeyEditDialog>().Instance.PreviewRun
        ?? throw new InvalidOperationException("No preview run has started yet.");

    protected static ProfileDto Profile(string name, string header, string footer = "") =>
        new(Guid.NewGuid(), name, false, header, footer, DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);

    protected const string CapsLockLayerHeader = """
        #Requires AutoHotkey v2.0

        *CapsLock::
        {
            SetKeyDelay -1
            Send "{Blind}{LCtrl DownR}"
        }
        """;

    protected async Task<IRenderedComponent<MudDialogProvider>> ShowDialogWithProfilesAsync(
        HotkeyEditModel item,
        params ProfileDto[] profiles)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotkeyEditDialog.Item)] = item,
                [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)profiles,
                [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };

            await dialogService.ShowAsync<HotkeyEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }
}
