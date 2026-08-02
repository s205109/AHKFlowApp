using AHKFlowApp.UI.Blazor.Components.Common;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Common;

public sealed class AhkCodePreviewPanelTests : BunitContext
{
    private readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();

    public AhkCodePreviewPanelTests()
    {
        Services.AddMudServices();
        Services.AddSingleton(_snackbar);
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<AhkCodePreviewPanel> RenderPanel(
        bool expanded = true,
        bool pending = false,
        string? error = null,
        string? blockedMessage = null,
        string? snippet = null,
        RenderFragment? snippetHeader = null) =>
        Render<AhkCodePreviewPanel>(parameters => parameters
            .Add(p => p.Expanded, expanded)
            .Add(p => p.Pending, pending)
            .Add(p => p.Error, error)
            .Add(p => p.BlockedMessage, blockedMessage)
            .Add(p => p.Snippet, snippet)
            .Add(p => p.SnippetHeader, snippetHeader));

    [Fact]
    public void Snippet_IsRenderedWithItsCopyButton()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel = RenderPanel(snippet: "^!k::Send(\"+{End}\")");

        panel.Find("[data-test=\"preview-snippet\"]").TextContent
            .Should().Be("^!k::Send(\"+{End}\")");
        panel.FindAll("[data-test=\"preview-copy\"]").Should().ContainSingle();
    }

    [Fact]
    public void Pending_ShowsTheSpinnerAndMarksTheSnippetStale()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel = RenderPanel(pending: true, snippet: "k::return");

        panel.FindAll("[data-test=\"preview-pending\"]").Should().ContainSingle();
        panel.Find("[data-test=\"preview-snippet\"]").ClassList.Should().Contain("preview-stale");
    }

    [Fact]
    public void Error_OutranksTheSnippet()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel =
            RenderPanel(error: "Something went wrong.", snippet: "k::return");

        panel.Find("[data-test=\"preview-error\"]").TextContent.Should().Contain("Something went wrong.");
        panel.FindAll("[data-test=\"preview-snippet\"]").Should().BeEmpty();
    }

    [Fact]
    public void BlockedMessage_ShowsOnlyWhenThereIsNoError()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel =
            RenderPanel(blockedMessage: "Fix the highlighted fields to see the generated code.");

        panel.Find("[data-test=\"preview-blocked\"]").TextContent
            .Should().Contain("Fix the highlighted fields");

        panel.Render(parameters => parameters
            .Add(p => p.BlockedMessage, "Fix the highlighted fields to see the generated code.")
            .Add(p => p.Error, "Boom."));

        panel.FindAll("[data-test=\"preview-blocked\"]").Should().BeEmpty();
    }

    [Fact]
    public void SnippetHeader_RendersAboveTheSnippet()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel = RenderPanel(
            snippet: "k::return",
            snippetHeader: builder =>
            {
                builder.OpenElement(0, "span");
                builder.AddAttribute(1, "data-test", "preview-delivery");
                builder.AddContent(2, "Clipboard");
                builder.CloseElement();
            });

        panel.FindAll("[data-test=\"preview-delivery\"]").Should().ContainSingle();
    }

    [Fact]
    public void SnippetHeader_IsNotRenderedWithoutASnippet()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel = RenderPanel(
            snippet: null,
            snippetHeader: builder =>
            {
                builder.OpenElement(0, "span");
                builder.AddAttribute(1, "data-test", "preview-delivery");
                builder.AddContent(2, "Clipboard");
                builder.CloseElement();
            });

        panel.FindAll("[data-test=\"preview-delivery\"]").Should().BeEmpty();
    }

    [Fact]
    public async Task Copy_PutsTheSnippetOnTheClipboardAndConfirms()
    {
        IRenderedComponent<AhkCodePreviewPanel> panel = RenderPanel(snippet: "k::return");

        await panel.Find("[data-test=\"preview-copy\"]").ClickAsync(new());

        JSInterop.VerifyInvoke("navigator.clipboard.writeText")
            .Arguments[0].Should().Be("k::return");
        _snackbar.Received(1).Add("Generated code copied.", Severity.Success,
            Arg.Any<Action<SnackbarOptions>?>(), Arg.Any<string?>());
    }
}
