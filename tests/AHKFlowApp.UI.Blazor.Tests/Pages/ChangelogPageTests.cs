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
