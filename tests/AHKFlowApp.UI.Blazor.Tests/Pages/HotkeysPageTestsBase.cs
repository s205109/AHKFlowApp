using System.Security.Claims;
using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public abstract class HotkeysPageTestsBase : BunitContext, IAsyncLifetime
{
    protected static readonly HotkeyKeyDto[] CatalogKeys =
    [
        new("F1", "Function keys", ["HotkeyKey"], true),
        new("n", "Letters & digits", ["HotkeyKey"], false),
    ];

    protected readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();
    protected readonly IProfilesApiClient _profilesApi = Substitute.For<IProfilesApiClient>();
    protected readonly ICategoriesApiClient _categoriesApi = Substitute.For<ICategoriesApiClient>();
    protected readonly IHotkeyKeyCatalog _catalog = Substitute.For<IHotkeyKeyCatalog>();
    protected readonly IKnownShortcutCatalog _knownShortcuts = Substitute.For<IKnownShortcutCatalog>();

    protected IRenderedComponent<MudDialogProvider>? _dialogProvider;

    protected static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    protected HotkeysPageTestsBase()
    {
        Services.AddSingleton(_api);

        IUserPreferencesService prefs = Substitute.For<IUserPreferencesService>();
        prefs.GetAsync(Arg.Any<CancellationToken>()).Returns(UserPreferences.Default);
        Services.AddSingleton(prefs);

        StubProfiles();
        Services.AddSingleton(_profilesApi);

        StubCategories();
        Services.AddSingleton(_categoriesApi);

        StubKeyCatalog(keysValid: true);
        Services.AddSingleton(_catalog);

        // The edit dialog and the list both inject this. The default is an empty catalog: most
        // page tests are about the grid and the dialog opening, not the notice.
        StubKnownShortcuts(new KnownShortcutCatalogDto([]));
        Services.AddSingleton(_knownShortcuts);

        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    protected IRenderedComponent<Hotkeys> RenderPage()
    {
        Render<MudPopoverProvider>();
        _dialogProvider = Render<MudDialogProvider>();
        return Render<Hotkeys>(p => p.AddCascadingValue(AuthenticatedState));
    }

    /// <summary>The dialog renders in its own root, so page assertions never see it.</summary>
    protected IRenderedComponent<MudDialogProvider> DialogProvider =>
        _dialogProvider ?? throw new InvalidOperationException("Render the page first.");

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    protected static HotkeyDto MakeHotkey(string description = "Open terminal", string key = "T") =>
        new(Guid.NewGuid(), [], true, description, key, true, false, false, false,
            HotkeyActionKind.Run, null, null, "wt.exe", RunTargetKind.Application, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    /// <summary>A Run row bound to Win+N — inline-editable, and its combo exercises the casing rule.</summary>
    protected static HotkeyDto OneRunHotkey(string key = "n") =>
        new(Guid.NewGuid(), [], true, "Open notepad", key, false, false, false, true,
            HotkeyActionKind.Run, null, null, "notepad.exe", RunTargetKind.Application, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    protected static HotkeyDto OneHotkeyOfKind(HotkeyActionKind kind)
    {
        HotkeyDto row = new(Guid.NewGuid(), [], true, "Kind row", "F1", false, false, false, true,
            kind, null, null, null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

        return kind switch
        {
            HotkeyActionKind.SendText => row with { Text = "hello" },
            HotkeyActionKind.SendKeys => row with { SendKeysContent = "^c" },
            HotkeyActionKind.Run => row with { RunTarget = "notepad.exe", RunTargetKind = RunTargetKind.Application },
            HotkeyActionKind.Window => row with { WindowOp = WindowOp.Minimize },
            HotkeyActionKind.Remap => row with { RemapDest = "F2" },
            HotkeyActionKind.Raw => row with { Body = "MsgBox \"hi\"" },
            _ => row,
        };
    }

    protected IRenderedComponent<Hotkeys> RenderPageWith(HotkeyDto dto, bool keysValid = true)
    {
        StubKeyCatalog(keysValid);
        StubList(Page(dto));

        IRenderedComponent<Hotkeys> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        return cut;
    }

    protected void StubKeyCatalog(bool keysValid)
    {
        _catalog.ForRoleAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult<IReadOnlyList<HotkeyKeyDto>>(
                [.. CatalogKeys.Where(k => k.Roles.Contains(call.Arg<string>()))]));
        _catalog.GroupOf(Arg.Any<string>())
            .Returns(call => CatalogKeys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.Group);
        _catalog.IsValidKey(Arg.Any<string>()).Returns(keysValid);
        _catalog.CanonicalizeAsync(Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult(call.Arg<string?>() ?? ""));
    }

    protected void StubKnownShortcuts(KnownShortcutCatalogDto catalog) =>
        _knownShortcuts.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ValueTask.FromResult<KnownShortcutCatalogDto?>(catalog));

    /// <summary>The Windows use of Win+N, so a row bound to Win+N carries a marker.</summary>
    protected static KnownShortcutCatalogDto WinNCatalog() =>
        new([
            new KnownShortcutDto("windows.notepad", "n", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open Notepad")],
                null),
        ]);

    protected static ProfileDto MakeProfile(string name = "Work") =>
        new(Guid.NewGuid(), name, false, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    protected static PagedList<HotkeyDto> Page(params HotkeyDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    protected void StubList(PagedList<HotkeyDto> page) =>
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotkeyDto>>.Ok(page));

    protected void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<HotkeyListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotkeyDto>>.Failure(status, problem));

    protected void StubProfiles(params ProfileDto[] profiles) =>
        _profilesApi.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    protected void StubCategories(params CategoryDto[] categories)
    {
        PagedList<CategoryDto> page = new(categories, 1, 200, categories.Length, 1, false, false);
        _categoriesApi.ListAsync(Arg.Any<CategoryListRequest>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<CategoryDto>>.Ok(page));
    }

    /// <summary>Renders one inline-editable row and puts it into inline edit.</summary>
    protected IRenderedComponent<Hotkeys> StartInlineEdit(HotkeyDto dto)
    {
        IRenderedComponent<Hotkeys> cut = RenderPageWith(dto);

        cut.Find("button.start-edit").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"description-input\"]"));
        return cut;
    }

    // The key is a KeyPicker, not a plain text field: driving its ValueChanged is what a
    // selection from the dropdown does, without depending on popover/JS behaviour.
    protected static Task SetKeyAsync(IRenderedComponent<Hotkeys> cut, string? key) =>
        cut.InvokeAsync(() => cut.FindComponent<KeyPicker>().Instance.ValueChanged.InvokeAsync(key));

    // Both branches render at once — the scoped CSS only hides one — so every marker assertion
    // is scoped to the branch it is about.
    protected const string DesktopMarker = ".desktop-branch [data-test=\"known-shortcut-marker\"]";
    protected const string MobileMarker = ".mobile-branch [data-test=\"known-shortcut-marker\"]";
}
