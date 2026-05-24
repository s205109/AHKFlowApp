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
}
