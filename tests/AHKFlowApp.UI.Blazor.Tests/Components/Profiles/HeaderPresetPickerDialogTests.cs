using AHKFlowApp.UI.Blazor.Components.Profiles;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Profiles;

public sealed class HeaderPresetPickerDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IProfilesApiClient _api = Substitute.For<IProfilesApiClient>();

    private static readonly HeaderPresetCatalogDto Catalog = new(
    [
        new("capslock-modifier-layer", "Caps Lock works as Ctrl+Alt+Shift",
            "Hold Caps Lock instead of three keys.", "Keyboard layer", "; layer"),
        new("lock-keys-off", "Keep lock keys off",
            "Holds three keys off.", "Lock keys", "; locks"),
    ]);

    public HeaderPresetPickerDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private async Task<IRenderedComponent<MudDialogProvider>> OpenAsync(string header)
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HeaderPresetPickerDialog>(
                "Insert preset",
                new DialogParameters { [nameof(HeaderPresetPickerDialog.Header)] = header });
        });

        return provider;
    }

    [Fact]
    public async Task Dialog_ShowsEveryPresetGroupedByTag()
    {
        _api.GetHeaderPresetsAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<HeaderPresetCatalogDto>.Ok(Catalog));

        IRenderedComponent<MudDialogProvider> provider = await OpenAsync("");

        provider.WaitForAssertion(() =>
        {
            provider.Markup.Should().Contain("Keyboard layer");
            provider.Markup.Should().Contain("Lock keys");
            provider.Markup.Should().Contain("Caps Lock works as Ctrl+Alt+Shift");
            provider.Markup.Should().Contain("Keep lock keys off");
        });
    }

    [Fact]
    public async Task Dialog_OffersNoInsertButtonForAPresetAlreadyInTheHeader()
    {
        _api.GetHeaderPresetsAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<HeaderPresetCatalogDto>.Ok(Catalog));
        string header = HeaderPresetInserter.Insert("", Catalog.Presets[1]).Header;

        IRenderedComponent<MudDialogProvider> provider = await OpenAsync(header);

        provider.WaitForAssertion(() =>
        {
            provider.Markup.Should().Contain("Already in the header");
            provider.FindAll("button[data-test=\"header-preset-insert-lock-keys-off\"]")
                .Should().BeEmpty();
            provider.FindAll("button[data-test=\"header-preset-insert-capslock-modifier-layer\"]")
                .Should().ContainSingle();
        });
    }

    [Fact]
    public async Task Dialog_ShowsTheApiErrorWhenTheCatalogCannotBeLoaded()
    {
        _api.GetHeaderPresetsAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<HeaderPresetCatalogDto>.Failure(ApiResultStatus.ServerError, null));

        IRenderedComponent<MudDialogProvider> provider = await OpenAsync("");

        provider.WaitForAssertion(() =>
            provider.FindAll("div.mud-alert").Should().NotBeEmpty());
    }
}
