using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class DownloadsPageTests : BunitContext, IAsyncLifetime
{
    private readonly IProfilesApiClient _profiles = Substitute.For<IProfilesApiClient>();
    private readonly IDownloadsApiClient _downloads = Substitute.For<IDownloadsApiClient>();
    private readonly IFileSaver _saver = Substitute.For<IFileSaver>();

    private static readonly Task<AuthenticationState> AuthenticatedState =
        Task.FromResult(new AuthenticationState(
            new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "testuser")], "test"))));

    public DownloadsPageTests()
    {
        Services.AddSingleton(_profiles);
        Services.AddSingleton(_downloads);
        Services.AddSingleton(_saver);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    private IRenderedComponent<Downloads> RenderPage()
    {
        Render<MudPopoverProvider>();
        return Render<Downloads>(p => p.AddCascadingValue(AuthenticatedState));
    }

    private static ProfileDto MakeProfile(string name) =>
        new(Guid.NewGuid(), name, false, "header", "footer", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private void StubProfileList(params ProfileDto[] profiles) =>
        _profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Ok(profiles));

    [Fact]
    public void Page_OnLoad_RendersTitleAndDownloadAllButton()
    {
        StubProfileList(MakeProfile("Work"));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.download-all").Should().NotBeNull());

        cut.Markup.Should().Contain("Downloads");
        cut.Markup.Should().Contain("Download all");
    }

    [Fact]
    public void Page_OnLoad_RendersOneDownloadButtonPerProfile()
    {
        StubProfileList(MakeProfile("Work"), MakeProfile("Personal"));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.FindAll("button.download-profile").Should().HaveCount(2));
    }

    [Fact]
    public Task Click_PerProfileDownload_FetchesAndCallsFileSaver()
    {
        ProfileDto work = MakeProfile("Work");
        StubProfileList(work);
        FileDownload payload = new([0x41, 0x42], "ahkflow_Work.ahk", "text/plain; charset=utf-8");
        _downloads.GetProfileScriptAsync(work.Id, Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(payload));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.download-profile"));
        cut.Find("button.download-profile").Click();

        // filename is {yyyyMMdd_HHmmss}_ahkflow_Work.ahk — assert suffix, not exact timestamp
        return _saver.Received(1).SaveAsync(
            Arg.Is<string>(n => n.EndsWith("_ahkflow_Work.ahk")),
            "text/plain; charset=utf-8",
            Arg.Is<byte[]>(b => b.SequenceEqual(payload.Content)));
    }

    [Fact]
    public Task Click_DownloadAll_FetchesZipAndCallsFileSaver()
    {
        StubProfileList(MakeProfile("Work"));
        FileDownload zip = new([0x50, 0x4B, 0x05, 0x06], "ahkflow_scripts.zip", "application/zip");
        _downloads.GetAllProfileScriptsZipAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<FileDownload>.Ok(zip));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Find("button.download-all"));
        cut.Find("button.download-all").Click();

        // filename is {yyyyMMdd_HHmmss}_ahkflow_scripts.zip — assert suffix
        return _saver.Received(1).SaveAsync(
            Arg.Is<string>(n => n.EndsWith("_ahkflow_scripts.zip")),
            "application/zip",
            Arg.Is<byte[]>(b => b.SequenceEqual(zip.Content)));
    }

    [Fact]
    public void Page_OnProfileListError_ShowsErrorAlert()
    {
        _profiles.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<IReadOnlyList<ProfileDto>>.Failure(ApiResultStatus.NetworkError, null));

        IRenderedComponent<Downloads> cut = RenderPage();
        cut.WaitForAssertion(() => cut.Markup.Should().Contain("error"));
    }
}
