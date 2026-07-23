using AHKFlowApp.UI.Blazor.Components.Hotkeys;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotkeys;

public sealed class HotkeyMobileListTests : BunitContext, IAsyncLifetime
{
    public HotkeyMobileListTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static HotkeyEditModel Item(string description = "Open palette", string key = "K", bool ctrl = true, bool shift = true) =>
        new() { Id = Guid.NewGuid(), Description = description, Key = key, Ctrl = ctrl, Shift = shift };

    [Fact]
    public void Renders_ComboAndDescription_PerRow()
    {
        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [Item("Open palette", "K", ctrl: true, shift: true)])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("Ctrl+Shift+K");
        cut.Markup.Should().Contain("Open palette");
    }

    [Theory]
    // The shared ComboLabel upper-cases a single-character key only when a modifier is present;
    // a bare key keeps its casing, matching AHK's own convention.
    [InlineData(true, "c", "Ctrl+C")]
    [InlineData(false, "n", "n")]
    public void Renders_ComboLabel_WithSharedCasingRule(bool ctrl, string key, string expected)
    {
        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [Item("Row", key, ctrl: ctrl, shift: false)])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Find("td.trigger-cell code").TextContent.Should().Be(expected);
    }

    [Fact]
    public async Task ExpandedRow_ShowsActionChipAndSummary()
    {
        HotkeyEditModel item = Item();
        item.ActionKind = HotkeyActionKind.Run;
        item.RunTarget = "notepad.exe";

        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
            cut.Find("[data-test=\"action-chip\"]").TextContent.Should().Contain("Run"));
        cut.Find("tr.mobile-row-expanded").TextContent.Should().Contain("notepad.exe");
    }

    [Fact]
    public void EmptyState_DoesNotRenderTable()
    {
        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("No hotkeys yet.");
        cut.FindAll("table.mobile-list").Should().BeEmpty();
    }

    [Fact]
    public async Task EditButton_RaisesOnEdit()
    {
        HotkeyEditModel item = Item();
        HotkeyEditModel? edited = null;

        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnEdit, EventCallback.Factory.Create<HotkeyEditModel>(this, m => edited = m)));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        await cut.InvokeAsync(() => cut.Find("button.start-edit").Click());

        edited.Should().Be(item);
    }

    [Fact]
    public async Task DeleteButton_RaisesOnDelete()
    {
        HotkeyEditModel item = Item();
        HotkeyEditModel? deleted = null;

        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnDelete, EventCallback.Factory.Create<HotkeyEditModel>(this, m => deleted = m)));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        await cut.InvokeAsync(() => cut.Find("button.delete").Click());

        deleted.Should().Be(item);
    }

    [Fact]
    public async Task SelectModeToggle_RevealsCheckboxes()
    {
        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [Item()])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.FindAll("input.row-checkbox").Should().BeEmpty();

        await cut.InvokeAsync(() => cut.Find("button.toggle-select-mode").Click());

        cut.WaitForAssertion(() => cut.FindAll("input.row-checkbox").Should().NotBeEmpty());
    }

    [Fact]
    public async Task BulkDelete_RaisesOnBulkDelete_WithSelectedIds()
    {
        HotkeyEditModel a = Item("A", "A");
        HotkeyEditModel b = Item("B", "B");
        IReadOnlyList<Guid>? deletedIds = null;

        IRenderedComponent<HotkeyMobileList> cut = Render<HotkeyMobileList>(p => p
            .Add(c => c.Items, [a, b])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnBulkDelete, EventCallback.Factory.Create<IReadOnlyList<Guid>>(this, ids => deletedIds = ids)));

        await cut.InvokeAsync(() => cut.Find("button.toggle-select-mode").Click());

        cut.WaitForAssertion(() => cut.FindAll("input.row-checkbox").Count.Should().Be(2));
        cut.FindAll("input.row-checkbox")[0].Change(true);
        cut.FindAll("input.row-checkbox")[1].Change(true);

        await cut.InvokeAsync(() => cut.Find("button.bulk-delete-hotkeys").Click());

        deletedIds.Should().BeEquivalentTo(new[] { a.Id!.Value, b.Id!.Value });
    }
}
