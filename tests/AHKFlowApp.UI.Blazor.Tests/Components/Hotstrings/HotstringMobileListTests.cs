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

    private static HotstringEditModel RawItem(string trigger = "~ver", string replacement = ":*:~ver::\n{\nMsgBox A_AhkVersion\n}") =>
        new() { Id = Guid.NewGuid(), Trigger = trigger, Replacement = replacement, Kind = HotstringKind.Raw };

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
    public void EmptyState_WhileLoading_ShowsNoEmptyMessage()
    {
        // An empty list mid-load is not yet known to be empty — "No hotstrings yet." rendered
        // under the progress bar reads as a result the user does not actually have.
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.Loading, true)
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().NotContain("No hotstrings yet.");
        cut.Markup.Should().NotContain("No hotstrings match these filters.");
    }

    [Fact]
    public void EmptyState_WithActiveFilters_OffersClearFilters()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.HasActiveFilters, true)
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Markup.Should().Contain("No hotstrings match these filters.");
        cut.Markup.Should().NotContain("No hotstrings yet.");
        cut.FindAll("button.clear-filters").Should().ContainSingle();
    }

    [Fact]
    public async Task EmptyState_ClearFiltersButton_RaisesCallback()
    {
        bool cleared = false;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [])
            .Add(c => c.HasActiveFilters, true)
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[])
            .Add(c => c.OnClearFilters, EventCallback.Factory.Create(this, () => cleared = true)));

        await cut.InvokeAsync(() => cut.Find("button.clear-filters").Click());

        cleared.Should().BeTrue();
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

        // The cell leads with the kind chip, so the summary is what trails it — EndWith still proves
        // nothing else is appended after the format.
        cut.Find("td.replacement-cell").TextContent.Trim().Should().EndWith("yyyy-MM-dd");
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

        cut.Find("td.replacement-cell").TextContent.Trim()
            .Should().EndWith("Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex");
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

        cut.Find("td.replacement-cell").TextContent.Should().Contain("by the way");
        cut.FindAll("td.replacement-cell .macro-token-chip").Should().BeEmpty();
    }

    [Fact]
    public void TextRow_CollapsedCell_ShowsTintedKindChipNotDelivery()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [Item("btw", "by the way")])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        AngleSharp.Dom.IElement chip = cut.Find("td.trigger-cell .mud-chip");
        chip.TextContent.Should().Contain("Text");
        chip.ClassList.Should().Contain("kind-chip--text");
        cut.FindAll("[data-test=\"clipboard-delivery\"]").Should().BeEmpty();
    }

    [Theory]
    [InlineData(HotstringKind.DateTime, "Date", "kind-chip--datetime")]
    [InlineData(HotstringKind.Macro, "Macro", "kind-chip--macro")]
    public void CollapsedCell_NonTextKinds_ShowTheirOwnTintedChip(
        HotstringKind kind, string expectedLabel, string expectedClass)
    {
        HotstringEditModel item = Item();
        item.Kind = kind;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        AngleSharp.Dom.IElement chip = cut.Find("td.trigger-cell .mud-chip");
        chip.TextContent.Should().Contain(expectedLabel);
        chip.ClassList.Should().Contain(expectedClass);
    }

    [Fact]
    public void TextRow_CollapsedCell_ShowsClipboardIconFromEffectiveDelivery()
    {
        HotstringEditModel item = Item("long", "replacement text");
        item.EffectiveDelivery = HotstringDelivery.ClipboardPaste;

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.FindAll("[data-test=\"clipboard-delivery\"]").Should().HaveCount(1);
        cut.Find("td.trigger-cell .mud-chip").ClassList.Should().Contain("kind-chip--text");
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

    [Fact]
    public void MobileList_RawRow_ShowsFirstLineInCollapsedView()
    {
        HotstringEditModel item = RawItem(replacement: ":*:~ver::\n{\nMsgBox A_AhkVersion\n}");

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        cut.Find("td.replacement-cell").TextContent.Should().Contain(":*:~ver::");
        cut.Find("td.replacement-cell").TextContent.Should().NotContain("MsgBox A_AhkVersion");
    }

    [Fact]
    public void MobileList_RawRow_ShowsWarningBadgeCollapsed()
    {
        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [RawItem(), Item()])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        // The warning now rides on the Raw kind chip itself rather than a separate icon, so only
        // the Raw row carries it — and it is labelled for screen readers, not color-only.
        AngleSharp.Dom.IElement badge = cut.Find("[data-test=\"raw-kind-chip\"]");
        badge.TextContent.Should().Contain("Raw");
        badge.ClassList.Should().Contain("kind-chip--raw");
        badge.GetAttribute("aria-label").Should().Contain("Verbatim AutoHotkey definition");
        cut.FindAll("[data-test=\"raw-kind-chip\"]").Should().HaveCount(1);
    }

    [Fact]
    public async Task MobileList_RawExpanded_ShowsFullDefinitionAndWarningText()
    {
        HotstringEditModel item = RawItem(replacement: ":*:~ver::\n{\nMsgBox A_AhkVersion\n}");

        IRenderedComponent<HotstringMobileList> cut = Render<HotstringMobileList>(p => p
            .Add(c => c.Items, [item])
            .Add(c => c.Profiles, (IReadOnlyList<ProfileDto>)[])
            .Add(c => c.Categories, (IReadOnlyList<CategoryDto>)[]));

        await cut.InvokeAsync(() => cut.Find("tr.mobile-row").Click());

        cut.WaitForAssertion(() =>
        {
            cut.Find("[data-test=\"script-warning-expanded\"]").TextContent
                .Should().Contain("Runs arbitrary AutoHotkey code in the generated script.");
            cut.Find(".script-body").TextContent.Should().Be(":*:~ver::\n{\nMsgBox A_AhkVersion\n}");
        });
    }
}
