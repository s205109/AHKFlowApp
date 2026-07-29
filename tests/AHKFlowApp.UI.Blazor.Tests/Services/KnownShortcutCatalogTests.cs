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
    public async Task GetAsync_AfterInvalidate_FetchesAgain()
    {
        KnownShortcutCatalogDto second = new([]);
        IKnownShortcutsApiClient api = Substitute.For<IKnownShortcutsApiClient>();
        api.ListAsync(Arg.Any<CancellationToken>()).Returns(
            ApiResult<KnownShortcutCatalogDto>.Ok(Sample),
            ApiResult<KnownShortcutCatalogDto>.Ok(second));
        var catalog = new KnownShortcutCatalog(api);

        await catalog.GetAsync();
        catalog.Invalidate();
        KnownShortcutCatalogDto? after = await catalog.GetAsync();

        await api.Received(2).ListAsync(Arg.Any<CancellationToken>());
        after.Should().BeSameAs(second);
    }

    [Fact]
    public async Task GetAsync_InvalidatedMidFetch_DoesNotCacheTheStaleResponse()
    {
        // The regression test for the generation counter. Without it the in-flight response is
        // written back after the invalidation and the next call serves pre-mutation data.
        TaskCompletionSource<KnownShortcutCatalogDto> pending = new();
        IKnownShortcutsApiClient api = Substitute.For<IKnownShortcutsApiClient>();
        api.ListAsync(Arg.Any<CancellationToken>()).Returns(_ => WaitThenOkAsync(pending));
        var catalog = new KnownShortcutCatalog(api);

        ValueTask<KnownShortcutCatalogDto?> inFlight = catalog.GetAsync();
        catalog.Invalidate();
        pending.SetResult(Sample);
        await inFlight;

        await catalog.GetAsync();

        await api.Received(2).ListAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Invalidate_BeforeAnyGet_IsHarmless()
    {
        IKnownShortcutsApiClient api = ApiReturning(Sample);
        var catalog = new KnownShortcutCatalog(api);

        catalog.Invalidate();

        (await catalog.GetAsync()).Should().BeSameAs(Sample);
    }

    private static async Task<ApiResult<KnownShortcutCatalogDto>> WaitThenOkAsync(
        TaskCompletionSource<KnownShortcutCatalogDto> tcs)
    {
        KnownShortcutCatalogDto catalog = await tcs.Task;
        return ApiResult<KnownShortcutCatalogDto>.Ok(catalog);
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
