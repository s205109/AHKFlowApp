using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class HotstringsPageKindTests : HotstringsPageTestsBase
{
    [Fact]
    public Task Page_PromoteExistingRow_OpensEditDialogWithKindToggle()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        // Carry a typed edit into the promotion.
        cut.WaitForAssertion(() => cut.Find("textarea[data-test=\"replacement-input\"]"));
        cut.Find("textarea[data-test=\"replacement-input\"]").Input("by the way!");
        cut.Find("button.promote-edit").Click();

        // The dialog renders into the provider's tree, carrying the typed value.
        provider.WaitForAssertion(() =>
        {
            provider.Find(".hotstring-edit-dialog");
            provider.Find("[data-test=\"kind-selector\"]");
            provider.FindComponent<global::AHKFlowApp.UI.Blazor.Components.Hotstrings.HotstringEditDialog>()
                .Instance.Item.Replacement.Should().Be("by the way!");
        });
        return Task.CompletedTask;
    }

    // Backlog 211: the first plan read the dialog's current values, so clearing profiles inline
    // and promoting the edit claimed the stored item applied to no profile.
    [Fact]
    public async Task Page_PromoteAfterClearingProfilesInline_ShowsNoNotice()
    {
        ProfileDto work = new(Guid.NewGuid(), "Work", false, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubProfiles(work);
        var dto = new HotstringDto(Guid.NewGuid(), [work.Id], false, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() => cut.Find("[data-test=\"profile-select\"]"));
        await cut.InvokeAsync(() => cut
            .FindComponents<global::AHKFlowApp.UI.Blazor.Components.Common.EntityMultiSelect>()
            .Single(s => s.Instance.DataTest == "profile-select")
            .Instance.SelectedIdsChanged.InvokeAsync([]));
        cut.Find("button.promote-edit").Click();

        // The dialog really holds the cleared state, so the empty notice list below means something.
        provider.WaitForAssertion(() =>
        {
            provider.Find(".hotstring-edit-dialog");
            HotstringEditModel item = provider
                .FindComponent<global::AHKFlowApp.UI.Blazor.Components.Hotstrings.HotstringEditDialog>().Instance.Item;
            item.AppliesToAllProfiles.Should().BeFalse();
            item.ProfileIds.Should().BeEmpty();
        });
        provider.FindAll("[data-test=\"no-profile-notice\"]").Should().BeEmpty();
    }

    [Fact]
    public Task Page_PromoteDraftThenCancel_RestoresInlineDraft()
    {
        StubList(Page());

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        cut.Find("button.promote-edit").Click();

        // Dialog opens in the provider tree; cancel it via the title back button.
        provider.WaitForAssertion(() => provider.Find(".hotstring-edit-dialog button.cancel-edit"));
        provider.Find(".hotstring-edit-dialog button.cancel-edit").Click();

        // The dialog closes and the inline draft edit is restored (its commit control reappears).
        provider.WaitForAssertion(() => provider.FindAll(".hotstring-edit-dialog").Should().BeEmpty());
        cut.WaitForAssertion(() =>
        {
            cut.Find("input[data-test=\"trigger-input\"]");
            cut.Find("button.commit-edit").Should().NotBeNull();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_PromoteDraft_DialogShowsTriggerInsideWordsUnticked()
    {
        StubList(Page());

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.add-hotstring"));
        cut.Find("button.add-hotstring").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"trigger-input\"]"));
        cut.Find("input[data-test=\"trigger-input\"]").Input("btw");
        cut.Find("button.promote-edit").Click();

        // The promoted dialog starts from the draft, and the draft starts from the model default.
        provider.WaitForAssertion(() =>
            ((AngleSharp.Html.Dom.IHtmlInputElement)provider.Find(
                ".hotstring-edit-dialog input[data-test=\"inside-words-checkbox\"]")).IsChecked.Should().BeFalse());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_RendersKindBadgeWithOptionGlyphs()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
            false, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
            HotstringKind.Text, IsCaseSensitive: true, OmitEndingCharacter: false,
            EffectiveDelivery: HotstringDelivery.Type);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // The Kind column reports the kind. Keystroke delivery is the unremarkable default and
            // is deliberately left unmarked — only clipboard delivery, which overwrites the user's
            // clipboard, earns an icon.
            cut.Find(".desktop-branch .kind-badge").TextContent.Should().Contain("Text");
            cut.FindAll(".desktop-branch [data-test=\"clipboard-delivery\"]").Should().BeEmpty();
            cut.Find(".option-glyphs").TextContent.Should().Be("*?C");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_ExplicitClipboardDelivery_ShowsClipboardIcon()
    {
        HotstringDto dto = new(Guid.NewGuid(), [], true, "long", "replacement", null,
            true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            Delivery: HotstringDelivery.ClipboardPaste, EffectiveDelivery: HotstringDelivery.ClipboardPaste);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // Kind chip plus a clipboard icon beside it; the icon carries the marker, not text.
            cut.Find(".desktop-branch .kind-badge .mud-chip").TextContent.Should().Contain("Text");
            cut.FindAll(".desktop-branch [data-test=\"clipboard-delivery\"]").Should().HaveCount(1);
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_AutoDeliveryLongReplacement_ShowsClipboardChipFromEffectiveDelivery()
    {
        // The list reads the server-resolved EffectiveDelivery, not the raw stored Delivery=Auto —
        // this is what makes a long Auto row legible as clipboard in the UI.
        HotstringDto dto = new(Guid.NewGuid(), [], true, "long", "replacement", null,
            true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow,
            Delivery: HotstringDelivery.Auto, EffectiveDelivery: HotstringDelivery.ClipboardPaste);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.FindAll(".desktop-branch [data-test=\"clipboard-delivery\"]").Should().HaveCount(1);
            cut.FindAll(".desktop-branch [data-test=\"hotstring-delivery\"]").Should().BeEmpty();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_OmitEndingCharacter_SuppressedWhenExpandImmediately()
    {
        // OmitEndingCharacter can be true alongside IsEndingCharacterRequired=false (the dialog only
        // disables the checkbox, it doesn't clear the value) — the badge must hide "O" here exactly
        // like the emitter suppresses the O option under *.
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null,
            false, false, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null,
            HotstringKind.Text, IsCaseSensitive: false, OmitEndingCharacter: true);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
            cut.Find(".option-glyphs").TextContent.Should().Be("*"));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_Edit_NonInlineEditableRow_OpensDialogWithItem()
    {
        // MudDialogProvider renders dialog content into its own root, not into the component that
        // called ShowAsync — so the dialog markup must be queried on `provider`, not on `cut`
        // (RenderPage() discards its MudDialogProvider reference; render it manually here instead,
        // matching the pattern in HotstringEditDialogTests.cs).
        // Raw is not inline-editable, so the single Edit button must route to the dialog.
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", ":*:btw::by the way", null,
            true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, Kind: HotstringKind.Raw);
        StubList(Page(dto));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();
        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>(p => p.AddCascadingValue(AuthenticatedState));

        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        provider.WaitForAssertion(() =>
            provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Contain("by the way"));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_DateTimeRow_ShowsDateTimeSummaryInReplacementColumn()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "now", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.DateTime,
            DateTimeFormat: "yyyy-MM-dd");
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("yyyy-MM-dd"));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_MacroRow_RendersTokenChipsNotRawSyntax()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "greet", "Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Macro);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // Scoped to the desktop grid: the mobile branch is also in the DOM (hidden by
            // CSS) and intentionally renders the raw macro text in its collapsed rows.
            string grid = cut.Find(".hotstrings-grid").TextContent;
            grid.Should().NotContain("{{key:Enter}}");
            grid.Should().NotContain("{{cursor}}");
            grid.Should().Contain("{{first_name}}");
            grid.Should().Contain("Enter");
            grid.Should().Contain("⌖ cursor");
            cut.FindAll(".hotstrings-grid .macro-token-chip").Count.Should().Be(2);
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_MacroRow_EscapedLiteralOnly_RendersPlainTextNoChip()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "esc", "{{{{first_name}}}}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Macro);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("{{first_name}}");
            cut.FindAll(".hotstrings-grid .macro-token-chip").Should().BeEmpty();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_TextRow_ReplacementCell_HasNoMacroChips()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Text);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Markup.Should().Contain("by the way");
            cut.FindAll(".hotstrings-grid .macro-token-chip").Should().BeEmpty();
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EveryKind_RendersExactlyOneEditButtonPerRow()
    {
        // Every row gets exactly one Edit button regardless of kind — its behavior branches
        // internally (inline for Text with no context, dialog otherwise), it's not two buttons.
        var dateTimeDto = new HotstringDto(Guid.NewGuid(), [], true, "now", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.DateTime,
            DateTimeFormat: "yyyy-MM-dd");
        var textDto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Text);
        StubList(Page(dateTimeDto, textDto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.FindAll("button.edit").Count.Should().Be(2));
        return Task.CompletedTask;
    }

    [Fact]
    public async Task Page_KindFilter_ReloadsDataWithSelectedKind()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"kind-filter\"]"));

        IRenderedComponent<MudSelect<HotstringKind?>> desktopKindFilter = cut
            .FindComponents<MudSelect<HotstringKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"kind-filter\""));
        await cut.InvokeAsync(() => desktopKindFilter.Instance.ValueChanged.InvokeAsync(HotstringKind.DateTime));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotstringListRequest>(r => r.Kind == HotstringKind.DateTime),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public Task Page_PromoteButton_SaysChangeKindNotChangeType()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find("button.edit"));
        cut.Find("button.edit").Click();

        cut.WaitForAssertion(() =>
        {
            // Both the visible tooltip and the accessible name. CONTEXT.md lists "type" under
            // Avoid for Kind, so a screen reader must not hear the retired word either.
            AngleSharp.Dom.IElement promote = cut.Find("button.promote-edit");
            promote.GetAttribute("title").Should().Be("More options / change kind");
            promote.GetAttribute("aria-label").Should().Be("More options / change kind");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_KindFilter_IsLabelledKindNotType()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            // CONTEXT.md lists "type" under Avoid for Kind. Lock the label so it cannot drift back.
            IRenderedComponent<MudSelect<HotstringKind?>> desktop = cut
                .FindComponents<MudSelect<HotstringKind?>>()
                .Single(c => c.Markup.Contains("data-test=\"kind-filter\""));
            desktop.Instance.Label.Should().Be("Kind");

            IRenderedComponent<MudSelect<HotstringKind?>> mobile = cut
                .FindComponents<MudSelect<HotstringKind?>>()
                .Single(c => c.Markup.Contains("data-test=\"kind-filter-mobile\""));
            mobile.Instance.Label.Should().Be("Kind");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_RawRow_ShowsFirstLineMonospaceEllipsis()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "~ver", ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Raw);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement summary = cut.Find(".hotstrings-grid .script-summary");
            summary.TextContent.Should().Be(":*:~ver::");
            summary.TextContent.Should().NotContain("MsgBox A_AhkVersion");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_RawRow_ShowsWarningColoredBadgeWithAccessibleText()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "~ver", ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Raw);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement badge = cut.Find(".kind-badge .mud-chip");
            badge.TextContent.Should().Contain("Raw");
            badge.ClassList.Should().Contain("kind-chip--raw");
            // Warning must be conveyed semantically, not just via color — screen readers read the
            // aria-label, not the CSS warning color.
            badge.GetAttribute("aria-label").Should()
                .Contain("Raw").And.Contain("Verbatim AutoHotkey definition");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_DateTimeRow_ShowsInfoColoredBadge()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "now", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.DateTime,
            DateTimeFormat: "yyyy-MM-dd");
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement badge = cut.Find(".kind-badge .mud-chip");
            badge.TextContent.Should().Contain("Date");
            badge.ClassList.Should().Contain("kind-chip--datetime");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_MacroRow_ShowsSuccessColoredBadge()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "greet", "hello", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Macro);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            AngleSharp.Dom.IElement badge = cut.Find(".kind-badge .mud-chip");
            badge.TextContent.Should().Contain("Macro");
            badge.ClassList.Should().Contain("kind-chip--macro");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_Categories_RenderOutlinedAccentChips()
    {
        var categoryId = Guid.NewGuid();
        StubCategories(new CategoryDto(categoryId, "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, CategoryIds: [categoryId]);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            IReadOnlyList<AngleSharp.Dom.IElement> categoryChips = [.. cut.FindAll(".mud-table-cell .mud-chip")
                .Where(chip => chip.TextContent.Contains("Work"))];
            categoryChips.Should().NotBeEmpty();
            categoryChips.Should().OnlyContain(chip => chip.ClassList.Contains("mud-chip-outlined"));
            // Categories carry the brand accent, not MudBlazor's default grey. Outlined + accent is
            // a deliberately separate channel from the tinted, filled kind chips in the Kind column.
            categoryChips.Should().OnlyContain(chip =>
                chip.ClassList.Any(c => c.Contains("primary", StringComparison.OrdinalIgnoreCase)));
        });
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_KindColumnHeader_ShowsGlyphLegendHelpIcon()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find(".kind-legend-help").Should().NotBeNull());
    }

    [Fact]
    public async Task Page_SelectedRow_GetsSelectedRowClass()
    {
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("tbody tr"));

        await cut.InvokeAsync(() => cut.Find("tbody tr input[type=\"checkbox\"]").Change(true));

        cut.WaitForAssertion(() => cut.Find("tbody tr.selected-row").Should().NotBeNull());
    }

    [Fact]
    public Task Page_RawRow_SuppressesOptionGlyphsAndTooltipFlags()
    {
        // A Raw row can hold IsTriggerInsideWord=true from whatever client sent it, but its options live in the
        // verbatim text — the structured flag glyphs ("?") and tooltip flag phrases must not show.
        var dto = new HotstringDto(Guid.NewGuid(), [], true, "~ver", ":*:~ver::\n{\nMsgBox A_AhkVersion\n}",
            null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, HotstringKind.Raw);
        StubList(Page(dto));

        IRenderedComponent<Hotstrings> cut = RenderPage();

        cut.WaitForAssertion(() =>
        {
            cut.Find(".hotstrings-grid .option-glyphs").TextContent.Should().BeEmpty();
            cut.Find(".hotstrings-grid .kind-badge").TextContent.Should().Contain("Raw");
        });
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_KindFilter_ListsAllFourKinds()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"kind-filter\"]"));

        // Desktop + mobile selects each render all HotstringKind items — 4 kinds x 2 selects.
        IReadOnlyList<HotstringKind?> allValues = [.. cut.FindComponents<MudSelectItem<HotstringKind?>>()
            .Select(c => c.Instance.Value)];

        allValues.Should().HaveCount(8);
        allValues.Distinct().Should().BeEquivalentTo(
            [HotstringKind.Text, HotstringKind.DateTime, HotstringKind.Macro, HotstringKind.Raw]);
    }

    [Fact]
    public async Task Page_MobileKindFilter_ReloadsDataWithSelectedKind()
    {
        StubList(Page());

        IRenderedComponent<Hotstrings> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("[data-test=\"kind-filter-mobile\"]"));

        IRenderedComponent<MudSelect<HotstringKind?>> mobileKindFilter = cut
            .FindComponents<MudSelect<HotstringKind?>>()
            .Single(c => c.Markup.Contains("data-test=\"kind-filter-mobile\""));
        await cut.InvokeAsync(() => mobileKindFilter.Instance.ValueChanged.InvokeAsync(HotstringKind.DateTime));

        cut.WaitForAssertion(() => _api.Received().ListAsync(
            Arg.Is<HotstringListRequest>(r => r.Kind == HotstringKind.DateTime),
            Arg.Any<CancellationToken>()));
    }
}
