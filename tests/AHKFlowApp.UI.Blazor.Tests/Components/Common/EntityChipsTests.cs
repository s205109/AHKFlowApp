using AHKFlowApp.UI.Blazor.Components.Common;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Common;

public sealed class EntityChipsTests : BunitContext, IAsyncLifetime
{
    public EntityChipsTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_a_name_chip_per_id()
    {
        var work = Guid.NewGuid();
        var personal = Guid.NewGuid();
        List<EntityOption> options = [new(work, "Work"), new(personal, "Personal")];

        IRenderedComponent<EntityChips> cut = Render<EntityChips>(ps => ps
            .Add(p => p.Ids, new[] { work, personal })
            .Add(p => p.Options, options));

        cut.Markup.Should().Contain("Work");
        cut.Markup.Should().Contain("Personal");
    }

    [Fact]
    public void Renders_single_any_chip_when_any_true()
    {
        var work = Guid.NewGuid();
        List<EntityOption> options = [new(work, "Work")];

        IRenderedComponent<EntityChips> cut = Render<EntityChips>(ps => ps
            .Add(p => p.Ids, new[] { work })
            .Add(p => p.Options, options)
            .Add(p => p.Any, true));

        cut.Markup.Should().Contain("Any");
        cut.Markup.Should().NotContain("Work");
    }

    [Fact]
    public void Falls_back_to_truncated_id_for_unknown_option()
    {
        var unknown = Guid.NewGuid();

        IRenderedComponent<EntityChips> cut = Render<EntityChips>(ps => ps
            .Add(p => p.Ids, new[] { unknown })
            .Add(p => p.Options, Array.Empty<EntityOption>()));

        cut.Markup.Should().Contain(unknown.ToString()[..8]);
    }
}
