using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class KnownShortcutCatalogTests
{
    private static readonly KnownShortcutCatalogDto Sample = new(
        [
            new KnownShortcutDto("windows.file-explorer", "e", false, false, false, true,
                [new ShortcutUseDto("Windows", ShortcutProtection.Normal, ShortcutScope.Global, "open File Explorer")],
                null),
        ]);

    // NSubstitute over an interface this project owns, matching HotkeyKeyCatalogTests. Counting
    // calls is the only way to observe caching at all, so a hand-written fake would restate the
    // same helpers with no gain.
    private static IKnownShortcutsApiClient ApiReturning(KnownShortcutCatalogDto catalog)
    {
        IKnownShortcutsApiClient api = Substitute.For<IKnownShortcutsApiClient>();
        api.ListAsync(Arg.Any<CancellationToken>()).Returns(ApiResult<KnownShortcutCatalogDto>.Ok(catalog));
        return api;
    }

    [Fact]
    public async Task GetAsync_CalledTwice_FetchesOnce()
    {
        IKnownShortcutsApiClient api = ApiReturning(Sample);
        var catalog = new KnownShortcutCatalog(api);

        await catalog.GetAsync();
        await catalog.GetAsync();

        await api.Received(1).ListAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task GetAsync_OnFailure_ReturnsNull()
    {
        IKnownShortcutsApiClient api = Substitute.For<IKnownShortcutsApiClient>();
        api.ListAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<KnownShortcutCatalogDto>.Failure(ApiResultStatus.ServerError, null));

        (await new KnownShortcutCatalog(api).GetAsync()).Should().BeNull();
    }

    [Fact]
    public async Task GetAsync_AfterFailure_RetriesOnNextCall()
    {
        // The regression test for the caching trap: a memoized failure would silence every warning
        // for the rest of the session, even after the server recovers.
        IKnownShortcutsApiClient api = Substitute.For<IKnownShortcutsApiClient>();
        api.ListAsync(Arg.Any<CancellationToken>()).Returns(
            ApiResult<KnownShortcutCatalogDto>.Failure(ApiResultStatus.ServerError, null),
            ApiResult<KnownShortcutCatalogDto>.Ok(Sample));
        var catalog = new KnownShortcutCatalog(api);

        KnownShortcutCatalogDto? first = await catalog.GetAsync();
        KnownShortcutCatalogDto? second = await catalog.GetAsync();

        first.Should().BeNull();
        second.Should().BeSameAs(Sample);
        await api.Received(2).ListAsync(Arg.Any<CancellationToken>());
    }
}
