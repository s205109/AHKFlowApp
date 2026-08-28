using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using Microsoft.JSInterop;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class ProfilesPageTests : BunitContext, IAsyncLifetime
{
    private readonly IProfilesApiClient _api = Substitute.For<IProfilesApiClient>();
    private readonly IDownloadsApiClient _downloads = Substitute.For<IDownloadsApiClient>();
    private readonly IFileSaver _saver = Substitute.For<IFileSaver>();
    private readonly ISnackbar _snackbar = Substitute.For<ISnackbar>();
    private readonly FakeTimeProvider _clock = new(new DateTimeOffset(2026, 7, 26, 14, 5, 9, TimeSpan.Zero));

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public ProfilesPageTests()
    {
        Services.AddSingleton(_api);
        Services.AddSingleton(_downloads);
        Services.AddSingleton(_saver);
        Services.AddSingleton<TimeProvider>(_clock);
        // The page calls the real downloader. It is sealed, so NSubstitute cannot fake it, and
        // every dependency it needs is already a substitute here.
        Services.AddSingleton<ProfileScriptDownloader>();
        Services.AddMudServices();
        // Registered after AddMudServices so this substitute wins over MudBlazor's own snackbar.
        Services.AddSingleton(_snackbar);
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private IRenderedComponent<Profiles> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<Profiles>(p => p.AddCascadingValue(AuthenticatedState));
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private static ProfileDto MakeProfile(string name = "Work", bool isDefault = false) =>
        new(Guid.NewGuid(), name, isDefault, "header text", "footer text", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private void StubList(params ProfileDto[] profiles) =>
        _api.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    private void StubListFailure(ApiResultStatus status, ApiProblemDetails? problem = null) =>
        _api.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Failure(status, problem));

    [Fact]
    public void Page_OnLoad_ShowsTitleAndButtons()
    {
        StubList();

        IRenderedComponent<Profiles> cut = RenderPage();

        cut.WaitForAssertion(() => cut.Find("button.add-profile").Should().NotBeNull());
        cut.Find("button.reload-profiles").Should().NotBeNull();
        cut.Markup.Should().Contain("Profiles");
    }

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Work"));

        cut.Markup.Should().Contain("Work");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        StubListFailure(ApiResultStatus.NetworkError);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }

    [Fact]
    public Task Page_AddAndCommit_CallsCreateWithCorrectName()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateProfileDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileDto>.Ok(MakeProfile("Personal")));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        cut.Find("input[data-test=\"profile-name-input\"]").Input("Personal");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateProfileDto>(d => d.Name == "Personal"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_EditExistingRow_CallsUpdateWithNewName()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);
        _api.UpdateAsync(dto.Id, Arg.Any<UpdateProfileDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileDto>.Ok(dto with { Name = "Work Updated" }));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        cut.Find("input[data-test=\"profile-name-input\"]").Input("Work Updated");
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => _api.Received(1).UpdateAsync(
            dto.Id,
            Arg.Is<UpdateProfileDto>(d => d.Name == "Work Updated"),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_Delete_CancelPreventsDeleteAsync()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);
        _api.DeleteAsync(dto.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult.Ok());

        // The stub answers the confirmation with "cancel". Without it the message box never
        // resolves in bUnit, and the delete handler would stay suspended, proving nothing.
        IDialogService dialogService = Substitute.For<IDialogService>();
        dialogService.ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>())
            .Returns(Task.FromResult<bool?>(false));
        Services.AddSingleton(dialogService);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.delete"));
        cut.Find("button.delete").Click();

        // The answered confirmation is the signal that the cancel path ran.
        cut.WaitForAssertion(() => dialogService.Received(1).ShowMessageBoxAsync(
            Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>(),
            Arg.Any<DialogOptions>()));

        _ = _api.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public Task Page_BlankName_BlocksCommit_AndShowsValidationMessage()
    {
        StubList();

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();

        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        // Leave name empty
        cut.Find("button.commit-edit").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Name is required"));
        _api.DidNotReceive().CreateAsync(Arg.Any<CreateProfileDto>(), Arg.Any<CancellationToken>());
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_ToggleExpand_ShowsChildRowContent()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.toggle-expand"));
        cut.Find("button.toggle-expand").Click();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("header text"));
    }

    [Fact]
    public void Page_PreviewRefresh_CallsDownloadsApiAndShowsScript()
    {
        ProfileDto dto = MakeProfile("Work");
        StubList(dto);
        _downloads.GetProfileScriptPreviewAsync(dto.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileScriptPreviewDto>.Ok(new ProfileScriptPreviewDto(
                "#Requires AutoHotkey v2.0\n::btw::by the way",
                1,
                0,
                DateTimeOffset.UtcNow)));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.toggle-expand"));
        cut.Find("button.toggle-expand").Click();

        cut.WaitForAssertion(() => cut.Find("button.profile-preview-refresh"));
        cut.Find("button.profile-preview-refresh").Click();

        cut.WaitForAssertion(() => _downloads.Received(1).GetProfileScriptPreviewAsync(
            dto.Id,
            Arg.Any<CancellationToken>()));
        cut.Markup.Should().Contain("::btw::by the way");
    }

    [Fact]
    public void Page_OnConflictResponse_ApiCalledAndNoException()
    {
        StubList();
        _api.CreateAsync(Arg.Any<CreateProfileDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<ProfileDto>.Failure(ApiResultStatus.Conflict,
                new ApiProblemDetails(null, "Conflict", 409, "Profile name already exists", null, null)));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();
        cut.WaitForAssertion(() => cut.Find("input[data-test=\"profile-name-input\"]"));
        cut.Find("input[data-test=\"profile-name-input\"]").Input("Work");
        cut.Find("button.commit-edit").Click();

        // MudBlazor snackbars render via portal and are not in the component DOM in bUnit.
        // Assert the API was called (proving the commit path ran and conflict was handled without crash).
        cut.WaitForAssertion(() => _api.Received(1).CreateAsync(
            Arg.Is<CreateProfileDto>(d => d.Name == "Work"),
            Arg.Any<CancellationToken>()));
    }

    private const string DownloadButtonSelector = "button.download-profile-script";

    private static readonly FileDownload ScriptPayload =
        new([0x41, 0x42], "ahkflow_Work.ahk", "text/plain; charset=utf-8");

    private void StubScript(ProfileDto profile) =>
        _downloads.GetProfileScriptAsync(profile.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(ScriptPayload));

    private void StubScriptFailure(ProfileDto profile) =>
        _downloads.GetProfileScriptAsync(profile.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Failure(ApiResultStatus.NetworkError, null));

    private void AssertNoSnackbar() =>
        _snackbar.DidNotReceive().Add(
            Arg.Any<string>(), Arg.Any<Severity>(),
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());

    [Fact]
    public void Download_Click_SavesTheScriptAndReportsIt()
    {
        ProfileDto work = MakeProfile("Work");
        StubList(work);
        StubScript(work);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find(DownloadButtonSelector));
        cut.Find(DownloadButtonSelector).Click();

        // Exact name — the stamp comes from the injected clock, so it is deterministic.
        cut.WaitForAssertion(() => _saver.Received(1).SaveAsync(
            "20260726_140509_ahkflow_Work.ahk",
            "text/plain; charset=utf-8",
            Arg.Is<byte[]>(b => b.SequenceEqual(ScriptPayload.Content))));
        _snackbar.Received(1).Add(
            "Downloaded 20260726_140509_ahkflow_Work.ahk", Severity.Success,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>());
    }

    [Fact]
    public void Download_ApiFails_ShowsTheErrorAndSavesNothing()
    {
        ProfileDto work = MakeProfile("Work");
        StubList(work);
        StubScriptFailure(work);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find(DownloadButtonSelector));
        cut.Find(DownloadButtonSelector).Click();

        cut.WaitForAssertion(() => _snackbar.Received(1).Add(
            "Unable to reach the API. Check your connection and try again.", Severity.Error,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));
        _saver.DidNotReceive().SaveAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<byte[]>());
    }

    [Fact]
    public void Download_RowBeingEdited_ButtonIsBlocked()
    {
        StubList(MakeProfile("Work"));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();

        // Blocked, not disabled: the button must stay focusable so a keyboard or touch user can
        // still read why it refuses.
        cut.WaitForAssertion(() =>
        {
            IElement button = cut.Find(DownloadButtonSelector);
            button.GetAttribute("aria-disabled").Should().Be("true");
            button.HasAttribute("disabled").Should().BeFalse();
        });
    }

    [Fact]
    public void Download_UnsavedNewRow_ButtonIsBlocked()
    {
        StubList();

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.add-profile"));
        cut.Find("button.add-profile").Click();

        cut.WaitForAssertion(() =>
        {
            IElement button = cut.Find(DownloadButtonSelector);
            button.GetAttribute("aria-disabled").Should().Be("true");
            button.HasAttribute("disabled").Should().BeFalse();
        });
    }

    [Fact]
    public void Download_BlockedButton_ExplainsWhy()
    {
        StubList(MakeProfile("Work"));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.start-edit"));
        cut.Find("button.start-edit").Click();

        cut.WaitForAssertion(() => cut.Find("[data-test=\"blocked-action\"]"));

        // The name says what the button does. The reason is a description, so it rides on
        // aria-describedby instead of being glued onto the name.
        IElement button = cut.Find(DownloadButtonSelector);
        button.GetAttribute("aria-label").Should().Be("Download the Work script");
        cut.Find($"#{button.GetAttribute("aria-describedby")}").TextContent
            .Should().Be("Save your changes first");
    }

    [Fact]
    public void Download_WhileOneRuns_EveryRowIsDisabled()
    {
        ProfileDto alpha = MakeProfile("Alpha");
        ProfileDto beta = MakeProfile("Beta");
        StubList(alpha, beta);
        TaskCompletionSource<ApiResult<FileDownload>> pending = new();
        _downloads.GetProfileScriptAsync(alpha.Id, Arg.Any<CancellationToken>()).Returns(pending.Task);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector).Should().HaveCount(2));
        cut.FindAll(DownloadButtonSelector)[0].Click();

        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector)
            .Should().OnlyContain(button => button.HasAttribute("disabled")));
    }

    [Fact]
    public void Download_AfterSuccess_EveryRowIsUsableAgain()
    {
        ProfileDto alpha = MakeProfile("Alpha");
        ProfileDto beta = MakeProfile("Beta");
        StubList(alpha, beta);
        TaskCompletionSource<ApiResult<FileDownload>> pending = new();
        _downloads.GetProfileScriptAsync(alpha.Id, Arg.Any<CancellationToken>()).Returns(pending.Task);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector).Should().HaveCount(2));
        cut.FindAll(DownloadButtonSelector)[0].Click();
        pending.SetResult(ApiResult<FileDownload>.Ok(ScriptPayload));

        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector)
            .Should().OnlyContain(button => !button.HasAttribute("disabled")));
    }

    [Fact]
    public void Download_AfterFailure_EveryRowIsUsableAgain()
    {
        ProfileDto alpha = MakeProfile("Alpha");
        ProfileDto beta = MakeProfile("Beta");
        StubList(alpha, beta);
        TaskCompletionSource<ApiResult<FileDownload>> pending = new();
        _downloads.GetProfileScriptAsync(alpha.Id, Arg.Any<CancellationToken>()).Returns(pending.Task);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector).Should().HaveCount(2));
        cut.FindAll(DownloadButtonSelector)[0].Click();
        pending.SetResult(ApiResult<FileDownload>.Failure(ApiResultStatus.NetworkError, null));

        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector)
            .Should().OnlyContain(button => !button.HasAttribute("disabled")));
    }

    [Fact]
    public void Download_FileSaverFails_ReportsItAndFreesEveryRow()
    {
        ProfileDto alpha = MakeProfile("Alpha");
        ProfileDto beta = MakeProfile("Beta");
        StubList(alpha, beta);
        StubScript(alpha);
        _saver.SaveAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<byte[]>())
            .Throws(new JSException("the browser refused the download"));

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.FindAll(DownloadButtonSelector).Should().HaveCount(2));
        cut.FindAll(DownloadButtonSelector)[0].Click();

        cut.WaitForAssertion(() => _snackbar.Received(1).Add(
            "Saving the file failed.", Severity.Error,
            Arg.Any<Action<SnackbarOptions>>(), Arg.Any<string>()));
        // A faulted event task skips Blazor's own re-render, so without the catch the rows stay
        // rendered as disabled even though the field behind them was cleared.
        cut.FindAll(DownloadButtonSelector)
            .Should().OnlyContain(button => !button.HasAttribute("disabled"));
    }

    [Fact]
    public void Download_RowEntersEditWhileRunning_KeepsTheSpinner()
    {
        ProfileDto work = MakeProfile("Work");
        StubList(work);
        TaskCompletionSource<ApiResult<FileDownload>> pending = new();
        _downloads.GetProfileScriptAsync(work.Id, Arg.Any<CancellationToken>()).Returns(pending.Task);

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find(DownloadButtonSelector));
        cut.Find(DownloadButtonSelector).Click();
        cut.Find("button.start-edit").Click();

        // The download is still running, so the row must keep saying so.
        cut.WaitForAssertion(() => cut.FindAll($"{DownloadButtonSelector} .mud-progress-circular")
            .Should().ContainSingle());
    }

    [Fact]
    public async Task Download_CancelledByLeavingThePage_ShowsNoMessage()
    {
        ProfileDto work = MakeProfile("Work");
        StubList(work);
        TaskCompletionSource<ApiResult<FileDownload>> pending = new();
        CancellationToken passedToken = CancellationToken.None;
        _downloads.GetProfileScriptAsync(work.Id, Arg.Any<CancellationToken>())
            .Returns(call =>
            {
                passedToken = call.Arg<CancellationToken>();
                return pending.Task;
            });

        IRenderedComponent<Profiles> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find(DownloadButtonSelector));
        cut.Find(DownloadButtonSelector).Click();

        // Leaving the page disposes the component, which cancels its token source.
        await Renderer.DisposeComponents();

        // The page must hand its own token to the downloader, and disposal must cancel it.
        // Without this the test would still pass on a page that passed CancellationToken.None.
        passedToken.CanBeCanceled.Should().BeTrue();
        passedToken.IsCancellationRequested.Should().BeTrue();

        pending.SetException(new OperationCanceledException(passedToken));
        await Task.Yield();

        AssertNoSnackbar();
    }

    [Fact]
    public async Task InsertPreset_WritesIntoTheEditorAndSavesNothing()
    {
        ProfileDto profile = MakeProfile();
        StubList(profile);
        _api.GetHeaderPresetsAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<HeaderPresetCatalogDto>.Ok(new HeaderPresetCatalogDto(
                [new HeaderPresetDto("lock-keys-off", "Keep lock keys off", "Holds three keys off.",
                    "Lock keys", "SetNumLockState \"AlwaysOff\"")])));
        IRenderedComponent<MudDialogProvider> dialogProvider = Render<MudDialogProvider>();
        IRenderedComponent<Profiles> cut = RenderPage();

        cut.Find("button.start-edit").Click();
        cut.Find("button.header-preset-open").Click();
        dialogProvider.WaitForElement("button[data-test=\"header-preset-insert-lock-keys-off\"]");
        await dialogProvider.InvokeAsync(() =>
            dialogProvider.Find("button[data-test=\"header-preset-insert-lock-keys-off\"]").Click());

        cut.WaitForAssertion(() =>
            cut.Markup.Should().Contain("; --- AHKFlow preset: lock-keys-off ---"));
        await _api.DidNotReceive().UpdateAsync(
            Arg.Any<Guid>(), Arg.Any<UpdateProfileDto>(), Arg.Any<CancellationToken>());
    }
}
