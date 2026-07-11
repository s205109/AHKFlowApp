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

    private static HotstringEditModel DateTimeItem(string trigger = "now", string format = "yyyy-MM-dd") =>
        new() { Id = Guid.NewGuid(), Trigger = trigger, Replacement = "", Kind = HotstringKind.DateTime, DateTimeFormat = format };

    private static HotstringEditModel MacroItem(string trigger = "greet", string replacement = "Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex") =>
        new() { Id = Guid.NewGuid(), Trigger = trigger, Replacement = replacement, Kind = HotstringKind.Macro };

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

    [Fact]
    public async Task ExpandedRow_ShowsCaseAndOmitEndingCharacterFlags()
    {
        HotstringEditModel item = Item();
        item.IsCaseSensitive = true;
        item.OmitEndingCharacter = true;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("Case:");
            cut.Markup.Should().Contain("Omit end-char:");
        });
    }

    [Fact]
    public void DateTimeRow_ShowsSummaryInReplacementCell()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [DateTimeItem()])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Find("td.replacement-cell").TextContent.Should().Be("yyyy-MM-dd");
    }

    [Fact]
    public async Task DateTimeRow_Expanded_ShowsFormatLine_NotReplacementLine()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [DateTimeItem()])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("Format:");
            cut.Markup.Should().NotContain("Replacement:");
        });
    }

    [Fact]
    public void MacroRow_CollapsedCell_RendersRawReplacementWithoutChips()
    {
        // Collapsed rows stay a single ellipsized text line for list density; the
        // token-chip rendering is reserved for the expanded details.
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [MacroItem()])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Find("td.replacement-cell").TextContent
            .Should().Be("Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex");
        cut.FindAll("td.replacement-cell .macro-token-chip").Should().BeEmpty();
    }

    [Fact]
    public async Task MacroRow_Expanded_ShowsChipsInReplacementLine()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [MacroItem()])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
        {
            string expanded = cut.Find("tr.mobile-row-expanded").TextContent;
            expanded.Should().Contain("Replacement:");
            expanded.Should().NotContain("{{key:Enter}}");
            expanded.Should().NotContain("{{cursor}}");
            expanded.Should().Contain("{{first_name}}");
            cut.FindAll("tr.mobile-row-expanded .macro-token-chip").Count.Should().Be(2);
        });
    }

    [Fact]
    public async Task EscapedLiteralOnlyMacro_Expanded_RendersUnescapedTextNoChip()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [MacroItem("esc", "{{{{first_name}}}}")])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
        {
            cut.Find("tr.mobile-row-expanded").TextContent.Should().Contain("{{first_name}}");
            cut.FindAll("tr.mobile-row-expanded .macro-token-chip").Should().BeEmpty();
        });
    }

    [Fact]
    public void TextRow_CollapsedCell_HasNoMacroChips()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [Item("btw", "by the way")])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Find("td.replacement-cell").TextContent.Should().Be("by the way");
        cut.FindAll("td.replacement-cell .macro-token-chip").Should().BeEmpty();
    }

    [Fact]
    public async Task ExpandedDetail_ContextedHotstring_ShowsContextRow()
    {
        HotstringEditModel item = Item();
        item.ContextMatchType = WindowMatchType.Executable;
        item.ContextValue = "notepad.exe";

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
        {
            cut.Find("[data-test=\"context-row\"]").TextContent.Should().Contain("exe:notepad.exe");
        });
    }

    [Fact]
    public async Task ExpandedDetail_GlobalHotstring_HidesContextRow()
    {
        HotstringEditModel item = Item();

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() => cut.Find("tr.mobile-row-expanded"));
        cut.FindAll("[data-test=\"context-row\"]").Should().BeEmpty();
    }
}
