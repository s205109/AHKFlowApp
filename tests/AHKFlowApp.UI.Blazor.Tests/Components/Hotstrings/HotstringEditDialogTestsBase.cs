using AHKFlowApp.UI.Blazor.Components.Common;
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using MudBlazor;
using MudBlazor.Extensions;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public abstract class HotstringEditDialogTestsBase : BunitContext, IAsyncLifetime
{
    protected readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();
    protected readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();

    /// <summary>The date the dialog's preview renders. Fixed, so a run on New Year's Eve reads the
    /// same year as the assertion. Mid-day, so the date is the same in UTC and in local time.
    /// Only the preview test reads it; nothing else in this class depends on the date.</summary>
    protected static readonly DateTimeOffset FixedNow = new(2031, 7, 23, 12, 0, 0, TimeSpan.Zero);

    protected HotstringEditDialogTestsBase()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(_snackbar);
        Services.AddSingleton<TimeProvider>(new FakeTimeProvider(FixedNow));
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    protected static void DisablePreviewDebounce(IRenderedComponent<MudDialogProvider> provider) =>
        provider.FindComponent<HotstringEditDialog>().Instance.PreviewDebounce = TimeSpan.Zero;

    /// <summary>The preview run in flight right now. Capture it while its generation is still
    /// current, then await it later to know that generation's response has been handled.</summary>
    protected static Task PreviewRun(IRenderedComponent<MudDialogProvider> provider) =>
        provider.FindComponent<HotstringEditDialog>().Instance.PreviewRun
        ?? throw new InvalidOperationException("No preview run has started yet.");

    /// <summary>Set by <see cref="RenderDialogAsync"/>. MudSelect renders its open menu into the
    /// popover provider's tree, not the dialog's, so a test that inspects menu items needs this.</summary>
    protected IRenderedComponent<MudPopoverProvider>? _popoverProvider;

    protected async Task<IRenderedComponent<MudDialogProvider>> RenderDialogAsync(
        HotstringEditModel? item = null,
        params ProfileDto[] profiles)
    {
        _popoverProvider = Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            DialogParameters parameters = new()
            {
                [nameof(HotstringEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)profiles,
                [nameof(HotstringEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
            };
            if (item is not null)
                parameters[nameof(HotstringEditDialog.Item)] = item;

            await dialogService.ShowAsync<HotstringEditDialog>("Edit", parameters,
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    protected static bool IsInsideWordsChecked(IRenderedComponent<MudDialogProvider> provider) =>
        ((AngleSharp.Html.Dom.IHtmlInputElement)provider.Find("input[data-test=\"inside-words-checkbox\"]")).IsChecked;

    protected static Task SelectFormatAsync(IRenderedComponent<MudDialogProvider> provider, string format) =>
        provider.InvokeAsync(() =>
            provider.FindComponent<MudSelect<string>>().Instance.ValueChanged.InvokeAsync(format));
}
