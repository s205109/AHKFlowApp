using AHKFlowApp.UI.Blazor.Components.KnownShortcuts;
using AHKFlowApp.UI.Blazor.DTOs;
using Bunit;
using FluentAssertions;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.KnownShortcuts;

public sealed class KnownShortcutUseActionsTests : BunitContext, IAsyncLifetime
{
    public KnownShortcutUseActionsTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static KnownShortcutUseRow Row(
        ShortcutRecordOrigin origin = ShortcutRecordOrigin.BuiltIn,
        bool ignored = false,
        Guid? recordId = null) =>
        new("browser.new-window", "Ctrl+N",
            new ManagedShortcutUseDto("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground,
                "open a new window", origin, recordId, ignored));

    [Theory]
    [InlineData(ShortcutRecordOrigin.Owner, false, "delete-use")]
    [InlineData(ShortcutRecordOrigin.BuiltIn, true, "restore-use")]
    [InlineData(ShortcutRecordOrigin.BuiltIn, false, "ignore-use")]
    public void OneButtonPerRow_ChosenByOriginAndState(
        ShortcutRecordOrigin origin, bool ignored, string expectedClass)
    {
        IRenderedComponent<KnownShortcutUseActions> cut = Render<KnownShortcutUseActions>(p => p
            .Add(c => c.Row, Row(origin, ignored, origin == ShortcutRecordOrigin.Owner ? Guid.NewGuid() : null)));

        cut.FindAll("button").Should().ContainSingle();
        cut.Find("button").ClassList.Should().Contain(expectedClass);
    }

    [Fact]
    public void TheButton_CarriesThePairThatNamesItsUse()
    {
        IRenderedComponent<KnownShortcutUseActions> cut =
            Render<KnownShortcutUseActions>(p => p.Add(c => c.Row, Row()));

        cut.Find("button.ignore-use").GetAttribute("data-shortcut-id").Should().Be("browser.new-window");
        cut.Find("button.ignore-use").GetAttribute("data-used-by").Should().Be("Chrome");
    }

    [Theory]
    // The button shows an icon and no text, so the accessible name is all a screen reader gets.
    // "Stop warning about this" does not say what "this" is.
    [InlineData(ShortcutRecordOrigin.BuiltIn, false, "ignore-use", "Stop warning that Chrome uses Ctrl+N")]
    [InlineData(ShortcutRecordOrigin.BuiltIn, true, "restore-use", "Warn again that Chrome uses Ctrl+N")]
    [InlineData(ShortcutRecordOrigin.Owner, false, "delete-use", "Delete the record that Chrome uses Ctrl+N")]
    public void TheButton_IsNamedForItsUse(
        ShortcutRecordOrigin origin, bool ignored, string cssClass, string expectedLabel)
    {
        IRenderedComponent<KnownShortcutUseActions> cut = Render<KnownShortcutUseActions>(p => p
            .Add(c => c.Row, Row(origin, ignored, origin == ShortcutRecordOrigin.Owner ? Guid.NewGuid() : null)));

        cut.Find($"button.{cssClass}").GetAttribute("aria-label").Should().Be(expectedLabel);
    }

    [Fact]
    public void TheButton_KeepsAShortHoverTooltip()
    {
        IRenderedComponent<KnownShortcutUseActions> cut =
            Render<KnownShortcutUseActions>(p => p.Add(c => c.Row, Row()));

        cut.Find("button.ignore-use").GetAttribute("title").Should().Be("Stop warning about this");
    }

    [Theory]
    [InlineData(ShortcutRecordOrigin.BuiltIn, false, "ignore-use")]
    [InlineData(ShortcutRecordOrigin.BuiltIn, true, "restore-use")]
    [InlineData(ShortcutRecordOrigin.Owner, false, "delete-use")]
    public void ClickingTheButton_RaisesTheMatchingEvent(
        ShortcutRecordOrigin origin, bool ignored, string cssClass)
    {
        KnownShortcutUseRow row = Row(origin, ignored, origin == ShortcutRecordOrigin.Owner ? Guid.NewGuid() : null);
        KnownShortcutUseRow? ignoredRow = null;
        KnownShortcutUseRow? restoredRow = null;
        KnownShortcutUseRow? deletedRow = null;

        IRenderedComponent<KnownShortcutUseActions> cut = Render<KnownShortcutUseActions>(p => p
            .Add(c => c.Row, row)
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
    public void WhileBusy_TheButtonIsDisabled()
    {
        // Two overlapping writes each end with their own reload, and the older answer could land
        // last. One at a time is what keeps the list honest.
        IRenderedComponent<KnownShortcutUseActions> cut = Render<KnownShortcutUseActions>(p => p
            .Add(c => c.Row, Row())
            .Add(c => c.Busy, true));

        cut.Find("button.ignore-use").HasAttribute("disabled").Should().BeTrue();
    }
}
