using System.Globalization;
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Components.Hotstrings;

public sealed class HotstringImportDialogTests : BunitContext, IAsyncLifetime
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();

    public HotstringImportDialogTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(Substitute.For<ISnackbar>());
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private async Task<IRenderedComponent<MudDialogProvider>> OpenDialogAsync()
    {
        Render<MudPopoverProvider>();
        IRenderedComponent<MudDialogProvider> provider = Render<MudDialogProvider>();

        await provider.InvokeAsync(async () =>
        {
            IDialogService dialogService = Services.GetRequiredService<IDialogService>();
            await dialogService.ShowAsync<HotstringImportDialog>("Import",
                new DialogParameters
                {
                    [nameof(HotstringImportDialog.Profiles)] = (IReadOnlyList<ProfileDto>)[],
                },
                new DialogOptions { FullScreen = true, CloseButton = false });
        });

        return provider;
    }

    [Fact]
    public async Task Confirm_DisabledBeforePreview()
    {
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeTrue());
    }

    [Fact]
    public async Task PreviewThenConfirm_CallsImportAndClosesDialog()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [new HotstringImportRowDto(1, "btw", "by the way", true, false, [], HotstringImportRowStatus.Ready, null)],
                ReadyCount: 1, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));
        _api.ImportAsync(Arg.Any<ImportHotstringsRequestDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportResultDto>.Ok(new HotstringImportResultDto(
                ImportedCount: 1, WarningCount: 0,
                Rows: [new HotstringImportRowDto(1, "btw", "by the way", true, false, [], HotstringImportRowStatus.Ready, null)])));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]").Input("::btw::by the way");
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());
        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeFalse());

        await provider.InvokeAsync(() => provider.Find("button.confirm-import").Click());

        await _api.Received(1).ImportAsync(Arg.Any<ImportHotstringsRequestDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task EditingScriptAfterPreview_DisablesConfirmUntilRePreviewed()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [new HotstringImportRowDto(1, "btw", "by the way", true, false, [], HotstringImportRowStatus.Ready, null)],
                ReadyCount: 1, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]").Input("::btw::by the way");
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());
        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeFalse());

        provider.Find("textarea[data-test=\"import-script\"]").Input("::btw::changed content");

        provider.WaitForAssertion(() =>
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeTrue());
    }

    // Backlog 172. MudBlazor renders maxlength=524288 unless the page sets one, and the browser
    // cuts a longer paste without a word. bUnit does not apply maxlength, so this pins the
    // attribute itself; HotstringImportPasteFlowTests proves the browser behaviour.
    [Fact]
    public async Task ScriptBox_MaxLength_IsAboveTheServerLimit()
    {
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        string? maxLength = provider.Find("textarea[data-test=\"import-script\"]").GetAttribute("maxlength");

        int.Parse(maxLength!, CultureInfo.InvariantCulture)
            .Should().BeGreaterThan(HotstringImportDialog.MaxScriptLength);
    }

    [Fact]
    public async Task PasteAboveLimit_ShowsTooLargeMessageAndDisablesPreview()
    {
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        int length = HotstringImportDialog.MaxScriptLength + 1;

        provider.Find("textarea[data-test=\"import-script\"]").Input(new string('x', length));

        string expected =
            $"This script is too large to import. It has {length.ToString("N0", CultureInfo.InvariantCulture)} characters. " +
            $"The limit is {HotstringImportDialog.MaxScriptLength.ToString("N0", CultureInfo.InvariantCulture)} characters.";
        provider.WaitForAssertion(() =>
        {
            provider.Find(".import-too-large").TextContent.Should().Contain(expected);
            provider.Find("button.preview-import").HasAttribute("disabled").Should().BeTrue();
        });
    }

    [Fact]
    public async Task PasteAtLimit_ShowsNoMessageAndPreviewsTheWholeScript()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [], ReadyCount: 0, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]")
            .Input(new string('x', HotstringImportDialog.MaxScriptLength));
        provider.FindAll(".import-too-large").Should().BeEmpty();
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());

        await _api.Received(1).PreviewImportAsync(
            Arg.Is<string>(s => s.Length == HotstringImportDialog.MaxScriptLength),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task CuttingAnOversizedScriptBackToTheLimit_ClearsMessageAndEnablesPreview()
    {
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();
        provider.Find("textarea[data-test=\"import-script\"]")
            .Input(new string('x', HotstringImportDialog.MaxScriptLength + 1));
        provider.WaitForAssertion(() => provider.FindAll(".import-too-large").Should().NotBeEmpty());

        provider.Find("textarea[data-test=\"import-script\"]")
            .Input(new string('x', HotstringImportDialog.MaxScriptLength));

        provider.WaitForAssertion(() =>
        {
            provider.FindAll(".import-too-large").Should().BeEmpty();
            provider.Find("button.preview-import").HasAttribute("disabled").Should().BeFalse();
        });
    }

    [Fact]
    public async Task Preview_ReplacementCell_UsesPreWrapWhitespace()
    {
        _api.PreviewImportAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<HotstringImportPreviewDto>.Ok(new HotstringImportPreviewDto(
                [new HotstringImportRowDto(1, "sig", "line one\nline two", true, false, [], HotstringImportRowStatus.Ready, null)],
                ReadyCount: 1, WarningCount: 0, DuplicateCount: 0, InvalidCount: 0)));

        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        provider.Find("textarea[data-test=\"import-script\"]").Input("::sig::line one`nline two");
        await provider.InvokeAsync(() => provider.Find("button.preview-import").Click());

        provider.WaitForAssertion(() =>
            provider.FindAll("td[style*='white-space: pre-wrap']").Should().NotBeEmpty());
    }

    [Fact]
    public async Task SelectingOversizedFile_ShowsErrorWithoutCrashing()
    {
        IRenderedComponent<MudDialogProvider> provider = await OpenDialogAsync();

        IRenderedComponent<MudFileUpload<IBrowserFile>> fileUpload =
            provider.FindComponent<MudFileUpload<IBrowserFile>>();

        OversizedBrowserFile oversizedFile = new();

        await provider.InvokeAsync(() => fileUpload.Instance.FilesChanged.InvokeAsync(oversizedFile));

        provider.WaitForAssertion(() =>
        {
            provider.Markup.Should().Contain("File exceeds the 1 MB limit.");
            provider.Find("button.confirm-import").HasAttribute("disabled").Should().BeTrue();
        });

        // The stubbed stream throws if the guard fails to short-circuit before OpenReadStream.
        oversizedFile.StreamOpened.Should().BeFalse();
    }

    private sealed class OversizedBrowserFile : IBrowserFile
    {
        public bool StreamOpened { get; private set; }

        public string Name => "oversized.ahk";
        public DateTimeOffset LastModified => DateTimeOffset.UtcNow;
        public long Size => 1_048_577;
        public string ContentType => "text/plain";

        public Stream OpenReadStream(long maxAllowedSize = 512000, CancellationToken cancellationToken = default)
        {
            StreamOpened = true;
            throw new IOException("Should not be called — the size guard must short-circuit first.");
        }
    }
}
