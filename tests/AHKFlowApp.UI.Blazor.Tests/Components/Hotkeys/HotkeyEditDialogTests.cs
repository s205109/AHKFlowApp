using AHKFlowApp.UI.Blazor.Components.Hotkeys;
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

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotkeys;

public sealed class HotkeyEditDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotkeysApiClient _api = Substitute.For<IHotkeysApiClient>();

    public HotkeyEditDialogTests()
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
            await dialogService.ShowAsync<HotkeyEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"key-input\"]").GetAttribute("value").Should().Be(""));
        provider.Find("input[data-test=\"description-input\"]").GetAttribute("value").Should().Be("");
    }

    [Fact]
    public async Task EditMode_PrefillsFieldsFromItem()
    {
        HotkeyEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Description = "Open palette",
            Key = "K",
            Ctrl = true,
            Shift = true,
        };

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotkeyEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotkeyEditDialog.Item)] = item,
                    [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"key-input\"]").GetAttribute("value").Should().Be("K"));
        provider.Find("input[data-test=\"description-input\"]").GetAttribute("value").Should().Be("Open palette");
    }

    [Fact]
    public async Task SaveInCreateMode_CallsCreateAsync()
    {
        HotkeyDto created = new(Guid.NewGuid(), [], true, "Open palette", "K", true, false, true, false,
            HotkeyActionKind.SendKeys, null, null, null, null, null, null, null,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(created));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotkeyEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"description-input\"]"));
        provider.Find("input[data-test=\"description-input\"]").Change("Open palette");
        provider.Find("input[data-test=\"key-input\"]").Change("K");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateHotkeyDto>(d => d.Description == "Open palette" && d.Key == "K"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveInEditMode_CallsUpdateAsync()
    {
        HotkeyEditModel item = new()
        {
            Id = Guid.NewGuid(),
            Description = "Open palette",
            Key = "K",
            Ctrl = true,
        };
        _api.UpdateAsync(item.Id!.Value, Arg.Any<UpdateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Ok(
                new HotkeyDto(item.Id.Value, [], true, "Open palette", "P", true, false, false, false,
                    HotkeyActionKind.SendKeys, null, null, null, null, null, null, null,
                    DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotkeyEditDialog>("Edit",
                new DialogParameters
                {
                    [nameof(HotkeyEditDialog.Item)] = item,
                    [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"key-input\"]"));
        provider.Find("input[data-test=\"key-input\"]").Change("P");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            item.Id.Value,
            Arg.Is<UpdateHotkeyDto>(d => d.Key == "P"),
            Arg.Any<CancellationToken>()));
    }

    [Fact]
    public async Task SaveConflict_ShowsKeyErrorInline()
    {
        _api.CreateAsync(Arg.Any<CreateHotkeyDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotkeyDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Hotkey already exists", null, null)));

        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotkeyEditDialog>("New",
                new DialogParameters
                {
                    [nameof(HotkeyEditDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                    [nameof(HotkeyEditDialog.Categories)] = (IReadOnlyList<CategoryDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        provider.WaitForAssertion(() => provider.Find("input[data-test=\"description-input\"]"));
        provider.Find("input[data-test=\"description-input\"]").Change("Open palette");
        provider.Find("input[data-test=\"key-input\"]").Change("K");
        provider.Find("button.commit-edit").Click();

        provider.WaitForAssertion(() => provider.Markup.Should().Contain("Hotkey already exists"));
        provider.FindAll(".mud-alert").Should().BeEmpty();
    }
}
