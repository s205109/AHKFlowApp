using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class ChangelogPageTests : BunitContext, IAsyncLifetime
{
    private const string ItemSelector = "[data-test=\"changelog-item\"]";

    private readonly IChangelogClient _client = Substitute.For<IChangelogClient>();

    public ChangelogPageTests()
    {
        Services.AddSingleton(_client);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void OnLoad_RendersLoadingState()
    {
        TaskCompletionSource<ApiResult<ChangelogDocumentDto>> tcs = new();
        _client.GetAsync(Arg.Any<CancellationToken>()).Returns(tcs.Task);

        IRenderedComponent<Changelog> cut = Render<Changelog>();

        cut.Markup.Should().Contain("mud-skeleton");
    }

    [Fact]
    public void OnSuccess_RendersUnreleasedEntrySectionsAndItems()
    {
        _client.GetAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<ChangelogDocumentDto>.Ok(SampleDocument())));

        IRenderedComponent<Changelog> cut = Render<Changelog>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("Changelog");
        cut.Markup.Should().Contain("Unreleased");
        cut.Markup.Should().Contain("Added");
        cut.Markup.Should().Contain("In-app changelog");
    }

    [Fact]
    public void OnFailure_RendersErrorAlert()
    {
        _client.GetAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<ChangelogDocumentDto>.Failure(ApiResultStatus.ServerError, null)));

        IRenderedComponent<Changelog> cut = Render<Changelog>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("Unable to load the changelog");
    }

    [Fact]
    public void OnEmptyDocument_RendersEmptyState()
    {
        _client.GetAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<ChangelogDocumentDto>.Ok(new ChangelogDocumentDto(1, []))));

        IRenderedComponent<Changelog> cut = Render<Changelog>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));

        cut.Markup.Should().Contain("No changelog entries are available");
    }

    // Backlog 176. The page used to print each entry with plain interpolation, so the markdown
    // markers of CHANGELOG.md showed on screen.
    [Fact]
    public void OnSuccess_RendersCodeSpanAsCodeElementWithoutBackticks()
    {
        IRenderedComponent<Changelog> cut = RenderWithItem("Run `ahkflow hotstring list` now.");

        cut.Find(ItemSelector + " code").TextContent.Should().Be("ahkflow hotstring list");
        cut.Find(ItemSelector).TextContent.Should().Be("Run ahkflow hotstring list now.");
    }

    [Fact]
    public void OnSuccess_RendersStrongSpanAsStrongElementWithoutAsterisks()
    {
        IRenderedComponent<Changelog> cut = RenderWithItem("Turn on **Trigger inside words** first.");

        cut.Find(ItemSelector + " strong").TextContent.Should().Be("Trigger inside words");
        cut.Find(ItemSelector).TextContent.Should().Be("Turn on Trigger inside words first.");
    }

    [Fact]
    public void OnSuccess_EntryStartingAndEndingWithSpans_KeepsEveryWordAndSpace()
    {
        IRenderedComponent<Changelog> cut = RenderWithItem("`T` and **bold**");

        cut.Find(ItemSelector + " code").TextContent.Should().Be("T");
        cut.Find(ItemSelector + " strong").TextContent.Should().Be("bold");
        cut.Find(ItemSelector).TextContent.Should().Be("T and bold");
    }

    [Fact]
    public void OnSuccess_WritesMarkupInAnEntryAsText()
    {
        IRenderedComponent<Changelog> cut = RenderWithItem(
            "<img src=x onerror=alert(1)> then `<script>alert(2)</script>` then **<b>bold</b>**");

        cut.FindAll(ItemSelector + " img").Should().BeEmpty();
        cut.FindAll(ItemSelector + " script").Should().BeEmpty();
        cut.FindAll(ItemSelector + " b").Should().BeEmpty();
        cut.Find(ItemSelector + " code").TextContent.Should().Be("<script>alert(2)</script>");
        cut.Find(ItemSelector + " strong").TextContent.Should().Be("<b>bold</b>");
        cut.Find(ItemSelector).TextContent.Should().StartWith("<img src=x onerror=alert(1)> then ");
    }

    private IRenderedComponent<Changelog> RenderWithItem(string item)
    {
        ChangelogDocumentDto document = new(
            1,
            [
                new ChangelogEntryDto(
                    "Unreleased",
                    Date: null,
                    IsUnreleased: true,
                    [new ChangelogSectionDto("Added", [item])])
            ]);
        _client.GetAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(ApiResult<ChangelogDocumentDto>.Ok(document)));

        IRenderedComponent<Changelog> cut = Render<Changelog>();
        cut.WaitForState(() => !cut.Markup.Contains("mud-skeleton"));
        return cut;
    }

    private static ChangelogDocumentDto SampleDocument() => new(
        1,
        [
            new ChangelogEntryDto(
                "Unreleased",
                Date: null,
                IsUnreleased: true,
                [
                    new ChangelogSectionDto("Added", ["In-app changelog"])
                ])
        ]);
}
