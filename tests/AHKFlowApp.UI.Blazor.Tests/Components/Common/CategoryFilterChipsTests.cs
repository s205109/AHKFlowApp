using AHKFlowApp.UI.Blazor.Components.Common;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Common;

public sealed class CategoryFilterChipsTests : BunitContext, IAsyncLifetime
{
    public CategoryFilterChipsTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_a_chip_per_category()
    {
        List<EntityOption> categories = [new(Guid.NewGuid(), "Email"), new(Guid.NewGuid(), "Coding")];

        IRenderedComponent<CategoryFilterChips> cut = Render<CategoryFilterChips>(ps => ps
            .Add(p => p.Categories, categories));

        cut.Markup.Should().Contain("Email");
        cut.Markup.Should().Contain("Coding");
    }

    [Fact]
    public void Renders_nothing_when_no_categories()
    {
        IRenderedComponent<CategoryFilterChips> cut = Render<CategoryFilterChips>(ps => ps
            .Add(p => p.Categories, Array.Empty<EntityOption>()));

        cut.Markup.Trim().Should().BeEmpty();
    }

    [Fact]
    public void Clicking_a_chip_raises_selected_ids_changed()
    {
        var emailId = Guid.NewGuid();
        IReadOnlyList<Guid>? captured = null;

        IRenderedComponent<CategoryFilterChips> cut = Render<CategoryFilterChips>(ps => ps
            .Add(p => p.Categories, new List<EntityOption> { new(emailId, "Email") })
            .Add(p => p.SelectedIdsChanged,
                EventCallback.Factory.Create<IReadOnlyList<Guid>>(this, ids => captured = ids)));

        cut.Find(".mud-chip").Click();

        captured.Should().NotBeNull();
        captured!.Should().Contain(emailId);
    }
}
