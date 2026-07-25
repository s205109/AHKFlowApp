using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Common;

public sealed class KeyPickerTests : BunitContext, IAsyncLifetime
{
    private static readonly HotkeyKeyDto[] Keys =
    [
        new("F1", "Function keys", ["HotkeyKey", "RemapDest"], true),
        new("c", "Letters & digits", ["HotkeyKey", "SendToken"], false),
        new("Volume_Up", "Media & browser", ["SendToken"], true),
    ];

    public KeyPickerTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private void SetupCatalog()
    {
        IHotkeyKeyCatalog catalog = Substitute.For<IHotkeyKeyCatalog>();
        // Mirrors the real ForRoleAsync: filter by role, then order by group so groups cluster.
        catalog.ForRoleAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(call => ValueTask.FromResult<IReadOnlyList<HotkeyKeyDto>>(
                [.. Keys.Where(k => k.Roles.Contains(call.Arg<string>()))
                        .OrderBy(k => k.Group, StringComparer.Ordinal)
                        .ThenBy(k => k.Canonical, StringComparer.OrdinalIgnoreCase)]));
        catalog.GroupOf(Arg.Any<string>())
            .Returns(call => Keys.FirstOrDefault(k => k.Canonical == call.Arg<string>())?.Group);
        Services.AddSingleton(catalog);
    }

    // MudAutocomplete requires a MudPopoverProvider in the render tree.
    private IRenderedComponent<KeyPicker> RenderPicker(Action<ComponentParameterCollectionBuilder<KeyPicker>> parameters)
    {
        Render<MudPopoverProvider>();
        return Render<KeyPicker>(parameters);
    }

    [Fact]
    public async Task SearchAsync_ReturnsOnlyKeysForTheConfiguredRole()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderPicker(p => p
            .Add(x => x.Role, "SendToken")
            .Add(x => x.Label, "Send key"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("", CancellationToken.None);

        matches.Should().BeEquivalentTo(["c", "Volume_Up"]);
    }

    [Fact]
    public async Task SearchAsync_FiltersByTypedFragmentCaseInsensitively()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderPicker(p => p
            .Add(x => x.Role, "SendToken"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("vol", CancellationToken.None);

        matches.Should().ContainSingle().Which.Should().Be("Volume_Up");
    }

    [Fact]
    public async Task SearchAsync_TypedVirtualKeyCodeIsOfferedVerbatim()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderPicker(p => p
            .Add(x => x.Role, "HotkeyKey"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("vk1B", CancellationToken.None);

        matches.Should().Contain("vk1B");
    }

    [Fact]
    public void Renders_WithConfiguredLabelAndDataTest()
    {
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderPicker(p => p
            .Add(x => x.Role, "HotkeyKey")
            .Add(x => x.Label, "Key")
            .Add(x => x.DataTest, "key-picker"));

        cut.Markup.Should().Contain("key-picker");
    }

    [Fact]
    public async Task SearchAsync_PreservesTheCatalogsGroupOrdering()
    {
        // MudAutocomplete 9.3.0 cannot render group headers, so clustering depends entirely on
        // the order ForRoleAsync returns. Re-sorting here would scatter the groups.
        SetupCatalog();
        IRenderedComponent<KeyPicker> cut = RenderPicker(p => p
            .Add(x => x.Role, "HotkeyKey"));

        IEnumerable<string> matches = await cut.Instance.SearchAsync("", CancellationToken.None);

        // Ordinal: "Function keys" < "Letters & digits", so F1 precedes c.
        matches.Should().ContainInOrder("F1", "c");
    }
}
