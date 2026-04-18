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

public sealed class HotstringsPageTests : BunitContext
{
    private readonly IHotstringsApiClient _api = Substitute.For<IHotstringsApiClient>();

    public HotstringsPageTests()
    {
        Services.AddSingleton(_api);
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    private static PagedList<HotstringDto> Page(params HotstringDto[] items) =>
        new(items, 1, 50, items.Length, 1, false, false);

    [Fact]
    public void Page_OnLoad_ShowsRowsFromApi()
    {
        var dto = new HotstringDto(Guid.NewGuid(), null, "btw", "by the way", true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Ok(Page(dto)));

        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>();
        cut.WaitForState(() => cut.Markup.Contains("btw"));

        cut.Markup.Should().Contain("by the way");
    }

    [Fact]
    public void Page_OnApiError_ShowsErrorAlert()
    {
        _api.ListAsync(Arg.Any<Guid?>(), Arg.Any<int>(), Arg.Any<int>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<PagedList<HotstringDto>>.Failure(ApiResultStatus.NetworkError, null));

        IRenderedComponent<Hotstrings> cut = Render<Hotstrings>();
        cut.WaitForState(() => cut.Markup.Contains("Unable to reach"));

        cut.Markup.Should().Contain("Unable to reach the API");
    }
}
