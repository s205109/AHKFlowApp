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
}
