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
            .Add(p => p.AppliesToAllProfiles, true));

        // "All profiles" is the glossary short form of "Apply to all profiles" (CONTEXT.md).
        // The old "Any" label was an avoided synonym, so assert it is gone for good.
        cut.Markup.Should().Contain("All profiles");
        cut.Markup.Should().NotContain(">Any<");
        cut.Markup.Should().NotContain("Work");
    }

    // Backlog 210: an item with no profile showed an empty Profiles cell.
    [Theory]
    [InlineData(true, false, false, 1)]   // a profile cell, no profile: the chip
    [InlineData(true, false, true, 0)]    // a profile cell with a profile: that name only
    [InlineData(false, false, false, 0)]  // a category cell with no categories: nothing
    [InlineData(true, true, false, 0)]    // Apply to all profiles: the All profiles chip only
    public void MarksNoProfile_OnlyWhereAskedAndOnlyWhenEmpty(bool markNoProfile, bool appliesToAll, bool hasProfile, int expected)
    {
        var work = Guid.NewGuid();
        Guid[] ids = hasProfile ? [work] : [];
        List<EntityOption> options = hasProfile ? [new(work, "Work")] : [];

        // The chip sits in a MudTooltip, which needs a popover provider.
        Render<MudBlazor.MudPopoverProvider>();
        IRenderedComponent<EntityChips> cut = Render<EntityChips>(ps => ps
            .Add(p => p.Ids, ids)
            .Add(p => p.Options, options)
            .Add(p => p.MarkNoProfile, markNoProfile)
            .Add(p => p.AppliesToAllProfiles, appliesToAll));

        cut.FindAll(".no-profile-chip").Should().HaveCount(expected);
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
