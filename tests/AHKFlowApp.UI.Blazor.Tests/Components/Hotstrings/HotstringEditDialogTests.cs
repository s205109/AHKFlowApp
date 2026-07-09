using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringEditDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();

    public HotstringEditDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public async Task CreateMode_RendersEmptyFields()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be(""));
        provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Be("");
    }

    [Fact]
    public async Task EditMode_PrefillsFieldsFromItem()
    {
        HotstringEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
            Description = "polite filler",
        };

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Item)] = item,
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]").GetAttribute("value").Should().Be("btw"));
        provider.Find("textarea[data-test=\"replacement-input\"]").TextContent.Should().Contain("by the way");
    }

    [Fact]
    public async Task SaveInCreateMode_CallsCreateAsync()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        provider.Find("input[data-test=\"trigger-input\"]").Change("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Change("by the way");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Trigger == "btw" && d.Replacement == "by the way"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveInEditMode_CallsUpdateAsync()
    {
        HotstringEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Trigger = "btw",
            Replacement = "by the way",
        };
        _api.UpdateAsync(item.Id!.Value, Arg.Any<UpdateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(
                new HotstringDto(item.Id.Value, [], true, "btw", "by the way!", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Item)] = item,
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("textarea[data-test=\"replacement-input\"]"));
        provider.Find("textarea[data-test=\"replacement-input\"]").Change("by the way!");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            item.Id.Value,
            Arg.Is<UpdateHotstringDto>(d => d.Replacement == "by the way!"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveConflict_ShowsTriggerErrorInline()
    {
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists", null, null)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        provider.Find("input[data-test=\"trigger-input\"]").Change("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Change("by the way");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Trigger already exists"));
        provider.FindAll(".mud-alert").Should().BeEmpty();
    }

    [Fact]
    public async Task SaveInCreateMode_WithCaseSensitiveChecked_SendsNewFlags()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"trigger-input\"]"));
        provider.Find("input[data-test=\"trigger-input\"]").Change("btw");
        provider.Find("textarea[data-test=\"replacement-input\"]").Change("by the way");
        provider.Find("input[data-test=\"case-sensitive-checkbox\"]").Change(true);
        provider.Find("input[data-test=\"omit-ending-checkbox\"]").Change(true);
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.IsCaseSensitive && d.OmitEndingCharacter),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task KindSelector_Renders()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]").Should().NotBeNull());
    }

    [Fact]
    public async Task SwitchToDateTime_WithEmptyReplacement_HidesReplacementAndShowsDateTimePanel()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();

        provider.WaitForAssertion(() =>
        {
            provider.FindAll("textarea[data-test=\"replacement-input\"]").Should().BeEmpty();
            provider.Find("[data-test=\"datetime-format-select\"]").Should().NotBeNull();
        });
    }

    [Fact]
    public async Task SelectingPreset_SetsFormatAndRoundTripsIntoSavedDto()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "date", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));

        await SelectFormatAsync(provider, "yyyy-MM-dd");

        provider.Find("input[data-test=\"trigger-input\"]").Change("date");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.DateTime
                && d.DateTimeFormat == "yyyy-MM-dd"
                && d.Replacement == ""),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SelectingCustom_RevealsCustomFormatField()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));

        await SelectFormatAsync(provider, "__custom__");

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-custom\"]").Should().NotBeNull());
    }

    [Fact]
    public async Task Preview_ShowsFormattedOutputForValidFormat_AndInvalidFormatFallback()
    {
        HotstringEditModel item = new() { Trigger = "d", DateTimeFormat = "yyyy", Kind = HotstringKind.DateTime };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-preview\"]").TextContent.Trim()
            .Should().Be(DateTime.Now.Year.ToString()));

        item.DateTimeFormat = "yyyy'unterminated";
        provider.Render();

        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-preview\"]").TextContent.Should().Contain("Invalid format"));
    }

    [Fact]
    public async Task OffsetSwitch_TogglingOnAndOff_AddsAndRemovesFieldsAndNullsDefaults()
    {
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));
        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"date-offset-switch\"]"));

        provider.FindAll("[data-test=\"date-offset-amount\"]").Should().BeEmpty();

        provider.Find("input[data-test=\"date-offset-switch\"]").Change(true);

        provider.WaitForAssertion(() =>
        {
            provider.Find("input[data-test=\"date-offset-amount\"]").GetAttribute("value").Should().Be("1");
            provider.Find("[data-test=\"date-offset-unit\"]").Should().NotBeNull();
        });

        provider.Find("input[data-test=\"date-offset-switch\"]").Change(false);

        provider.WaitForAssertion(() => provider.FindAll("[data-test=\"date-offset-amount\"]").Should().BeEmpty());
    }

    [Fact]
    public async Task Save_WithDateTimeKind_PostsDtoWithEmptyReplacement()
    {
        HotstringDto created = new(Guid.NewGuid(), [], true, "date", "", null, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotstringDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringDto>.Ok(created));

        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Contains("Date & time")).Click();
        provider.WaitForAssertion(() => provider.Find("[data-test=\"datetime-format-select\"]"));
        await SelectFormatAsync(provider, "yyyy-MM-dd");

        provider.Find("input[data-test=\"trigger-input\"]").Change("date");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotstringDto>(d => d.Kind == HotstringKind.DateTime && d.Replacement == ""),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SwitchAwayFromDateTime_WithFormatSet_PromptsConfirmation()
    {
        // MudBlazor's IDialogService.ShowMessageBoxAsync opens a MudMessageBox rendered by the
        // same MudDialogProvider used for the edit dialog itself. bUnit renders it inline, so we
        // assert on the underlying model state (via a re-render probe) rather than trying to
        // synchronously await the nested dialog's result from the click handler.
        HotstringEditModel item = new() { Trigger = "date", Kind = HotstringKind.DateTime, DateTimeFormat = "yyyy-MM-dd" };
        IRenderedComponent<MudDialogProvider> provider = await RenderDialogAsync(item);
        provider.WaitForAssertion(() => provider.Find("[data-test=\"kind-selector\"]"));

        provider.FindAll(".mud-toggle-item").First(e => e.TextContent.Trim() == "Text").Click();

        // A confirmation MudMessageBox should now be present in the DOM (rendered by the same
        // MudDialogProvider), and the underlying model must remain untouched until it resolves.
        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Switching to Text"));
        item.Kind.Should().Be(HotstringKind.DateTime);
        item.DateTimeFormat.Should().Be("yyyy-MM-dd");
    }

    private async Task<IRenderedComponent<MudDialogProvider>> RenderDialogAsync(HotstringEditModel? item = null)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };
            if (item is not null)
                parameters[nameof(HotstringEditDialog.Item)] = item;

            await dialogService.ShowAsync<HotstringEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    private static Task SelectFormatAsync(IRenderedComponent<MudDialogProvider> provider, string format) =>
        provider.InvokeAsync(() =>
            provider.FindComponent<MudSelect<string>>().Instance.ValueChanged.InvokeAsync(format));
}
