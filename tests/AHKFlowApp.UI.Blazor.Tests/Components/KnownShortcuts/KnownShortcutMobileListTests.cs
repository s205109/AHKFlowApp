using AHKFlowApp.UI.Blazor.Components.KnownShortcuts;
using AHKFlowApp.UI.Blazor.DTOs;
using Bunit;
using FluentAssertions;
using MudBlazor;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.KnownShortcuts;

public sealed class KnownShortcutMobileListTests : BunitContext, IAsyncLifetime
{
    public KnownShortcutMobileListTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync()
    {
        Render<MudPopoverProvider>();
        return Task.CompletedTask;
    }

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    /// <summary>Types the rows as the parameter expects, so no call site needs an inline cast.</summary>
    private static IReadOnlyList<KnownShortcutUseRow> Items(params KnownShortcutUseRow[] rows) => rows;

    private static KnownShortcutUseRow Row(
        string usedBy = "Chrome",
        string does = "open a new window",
        ShortcutScope scope = ShortcutScope.Foreground,
        ShortcutRecordOrigin origin = ShortcutRecordOrigin.BuiltIn,
        bool ignored = false) =>
        new("browser.new-window", "Ctrl+N",
            new ManagedShortcutUseDto(usedBy, ShortcutProtection.Normal, scope, does,
                origin, OwnerRecordId: null, IsIgnored: ignored));

    [Fact]
    public void EachRow_ShowsTheCombinationWhatUsesItAndWhatItDoes()
    {
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items(Row())));

        cut.Find("[data-test=\"known-shortcut-row\"]").TextContent.Should().Be("Ctrl+N");
        cut.Find(".used-by").TextContent.Should().Be("Chrome");
        cut.Find(".does").TextContent.Should().Be("open a new window");
    }

    [Theory]
    [InlineData(ShortcutScope.Global, "Anywhere")]
    [InlineData(ShortcutScope.Foreground, "Only in front")]
    public void EachRow_SaysWhereItApplies(ShortcutScope scope, string expected)
    {
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items(Row(scope: scope))));

        cut.Find(".scope").TextContent.Should().Be(expected);
    }

    [Fact]
    public void OneCombinationWithTwoUses_RendersTwoRows()
    {
        // A browser combination holds a Chrome use and an Edge use. Each is silenced on its own,
        // so each needs its own row and its own button.
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items(Row("Chrome"), Row("Edge"))));

        cut.FindAll("[data-test=\"known-shortcut-row\"]").Should().HaveCount(2);
        cut.FindAll("button.ignore-use").Should().HaveCount(2);
    }

    [Theory]
    // The list forwards all three events, not just the one. A missed wire-up on restore or delete
    // would leave a button that looks live and does nothing.
    [InlineData(ShortcutRecordOrigin.BuiltIn, false, "ignore-use")]
    [InlineData(ShortcutRecordOrigin.BuiltIn, true, "restore-use")]
    [InlineData(ShortcutRecordOrigin.Owner, false, "delete-use")]
    public void ClickingAnAction_RaisesThatEventWithThatRow(
        ShortcutRecordOrigin origin, bool ignored, string cssClass)
    {
        KnownShortcutUseRow row = Row(origin: origin, ignored: ignored);
        KnownShortcutUseRow? ignoredRow = null;
        KnownShortcutUseRow? restoredRow = null;
        KnownShortcutUseRow? deletedRow = null;

        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items(row))
            .Add(c => c.OnIgnore, r => ignoredRow = (KnownShortcutUseRow?)r)
            .Add(c => c.OnRestore, r => restoredRow = (KnownShortcutUseRow?)r)
            .Add(c => c.OnDelete, r => deletedRow = (KnownShortcutUseRow?)r));

        cut.Find($"button.{cssClass}").Click();

        KnownShortcutUseRow? raised = cssClass switch
        {
            "ignore-use" => ignoredRow,
            "restore-use" => restoredRow,
            _ => deletedRow,
        };
        raised.Should().Be(row);
    }

    [Fact]
    public void NoRows_SaysSo()
    {
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items()));

        cut.Markup.Should().Contain("No known shortcuts.");
    }

    [Fact]
    public void WhileLoading_ShowsProgress_AndHoldsTheEmptyStateBack()
    {
        // An empty list mid-load is not yet known to be empty, and "No known shortcuts." during a
        // fetch reads as a result. Holding the message back is not enough on its own: that left a
        // blank panel that reads as "nothing here" just as wrongly.
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items())
            .Add(c => c.Loading, true));

        cut.Markup.Should().NotContain("No known shortcuts.");
        cut.FindAll("[data-test=\"known-shortcut-loading\"]").Should().ContainSingle();
    }

    [Fact]
    public void WhenNotLoading_ThereIsNoProgressBar()
    {
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items(Row())));

        cut.FindAll("[data-test=\"known-shortcut-loading\"]").Should().BeEmpty();
    }

    [Fact]
    public void ALoadError_ReplacesTheList()
    {
        IRenderedComponent<KnownShortcutMobileList> cut = Render<KnownShortcutMobileList>(p => p
            .Add(c => c.Items, Items())
            .Add(c => c.LoadError, "The server did not answer."));

        cut.Markup.Should().Contain("The server did not answer.");
        cut.Markup.Should().NotContain("No known shortcuts.");
    }
}
