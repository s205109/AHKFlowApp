using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringMobileListTests : BunitContext, IAsyncLifetime
{
    public HotstringMobileListTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static HotstringEditModel Item(string trigger = "btw", string replacement = "by the way") =>
        new() { Id = Guid.NewGuid(), Trigger = trigger, Replacement = replacement };

    [Fact]
    public void Renders_TriggerAndReplacement_PerRow()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [Item("btw", "by the way"), Item("addr", "123 Main St")])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("btw");
        cut.Markup.Should().Contain("by the way");
        cut.Markup.Should().Contain("addr");
    }

    [Fact]
    public void EmptyState_DoesNotRenderTable()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("No hotstrings yet.");
        cut.FindAll("table.mobile-list").Should().BeEmpty();
    }

    [Fact]
    public async Task EditButton_RaisesOnEdit()
    {
        HotstringEditModel item = Item();
        HotstringEditModel? edited = null;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnEdit, EventCallback.Factory.Create<HotstringEditModel>(this, m => edited = m)));

        // Expand the row first
        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        await cut.InvokeAsync(() => cut.Find("button.start-edit").Click());

        edited.Should().Be(item);
    }

    [Fact]
    public async Task DeleteButton_RaisesOnDelete()
    {
        HotstringEditModel item = Item();
        HotstringEditModel? deleted = null;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnDelete, EventCallback.Factory.Create<HotstringEditModel>(this, m => deleted = m)));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        await cut.InvokeAsync(() => cut.Find("button.delete").Click());

        deleted.Should().Be(item);
    }

    [Fact]
    public async Task SelectModeToggle_RevealsCheckboxes()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
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
        HotstringEditModel a = Item("a", "x");
        HotstringEditModel b = Item("b", "y");
        IReadOnlyList<Guid>? deletedIds = null;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [a, b])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnBulkDelete, EventCallback.Factory.Create<IReadOnlyList<Guid>>(this, ids => deletedIds = ids)));

        await cut.InvokeAsync(() => cut.Find("button.toggle-select-mode").Click());

        cut.WaitForAssertion(() => cut.FindAll("input.row-checkbox").Count.Should().Be(2));
        cut.FindAll("input.row-checkbox")[0].Change(true);
        cut.FindAll("input.row-checkbox")[1].Change(true);

        await cut.InvokeAsync(() => cut.Find("button.bulk-delete-hotstrings").Click());

        deletedIds.Should().BeEquivalentTo(new[] { a.Id!.Value, b.Id!.Value });
    }
}
