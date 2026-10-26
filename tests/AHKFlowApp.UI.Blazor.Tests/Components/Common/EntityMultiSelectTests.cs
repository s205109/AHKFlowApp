using AHKFlowApp.UI.Blazor.Components.Common;
using Bunit;
using Bunit.Rendering;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Common;

public sealed class EntityMultiSelectTests : BunitContext, IAsyncLifetime
{
    public EntityMultiSelectTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    // MudSelect requires a MudPopoverProvider in the render tree.
    private IRenderedComponent<EntityMultiSelect> RenderWithPopover(Action<RenderTreeBuilder> addParameters)
    {
        IRenderedComponent<ContainerFragment> fragment = Render(builder =>
        {
            builder.OpenComponent<MudPopoverProvider>(0);
            builder.CloseComponent();
            builder.OpenComponent<EntityMultiSelect>(1);
            addParameters(builder);
            builder.CloseComponent();
        });

        return fragment.FindComponent<EntityMultiSelect>();
    }

    [Fact]
    public void Renders_label_and_forwards_data_test_attribute()
    {
        List<EntityOption> options = [new(Guid.NewGuid(), "Work")];

        IRenderedComponent<EntityMultiSelect> cut = RenderWithPopover(b =>
        {
            b.AddAttribute(2, nameof(EntityMultiSelect.Options), options);
            b.AddAttribute(3, nameof(EntityMultiSelect.Label), "Profiles");
            b.AddAttribute(4, nameof(EntityMultiSelect.DataTest), "profile-select");
        });

        cut.Markup.Should().Contain("Profiles");
        cut.Markup.Should().Contain("data-test=\"profile-select\"");
    }

    [Fact]
    public void Shows_selected_option_name_via_to_string_func()
    {
        var workId = Guid.NewGuid();
        List<EntityOption> options = [new(workId, "Work")];

        IRenderedComponent<EntityMultiSelect> cut = RenderWithPopover(b =>
        {
            b.AddAttribute(2, nameof(EntityMultiSelect.Options), options);
            b.AddAttribute(3, nameof(EntityMultiSelect.SelectedIds), (IReadOnlyCollection<Guid>)new[] { workId });
        });

        cut.Markup.Should().Contain("Work");
    }

    // Backlog 189. A picker in an inline edit row has no visible label, so AriaLabel is its name.
    // The selector names the input element, so the name sits on the field, not a wrapper.
    [Fact]
    public void AriaLabel_WhenSet_NamesTheInput()
    {
        IRenderedComponent<EntityMultiSelect> cut = RenderWithPopover(b =>
        {
            b.AddAttribute(2, nameof(EntityMultiSelect.Options), new List<EntityOption>());
            b.AddAttribute(3, nameof(EntityMultiSelect.DataTest), "profile-select");
            b.AddAttribute(4, nameof(EntityMultiSelect.AriaLabel), "Profiles");
        });

        cut.Find("input[data-test=\"profile-select\"]").GetAttribute("aria-label").Should().Be("Profiles");
    }

    // A dialog picker is named by its visible Label. An aria-label would replace that name.
    [Fact]
    public void AriaLabel_WhenUnset_RendersNoAriaLabel()
    {
        IRenderedComponent<EntityMultiSelect> cut = RenderWithPopover(b =>
        {
            b.AddAttribute(2, nameof(EntityMultiSelect.Options), new List<EntityOption>());
            b.AddAttribute(3, nameof(EntityMultiSelect.Label), "Profiles");
            b.AddAttribute(4, nameof(EntityMultiSelect.DataTest), "profile-select");
        });

        cut.Find("input[data-test=\"profile-select\"]").HasAttribute("aria-label").Should().BeFalse();
    }
}
