using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotkeyKeyCatalogTests
{
    private static readonly HotkeyKeyCatalogDto Sample = new(
        [
            new HotkeyKeyDto("F1", "Function keys", ["HotkeyKey", "SendToken", "RemapSource", "RemapDest"], true),
            new HotkeyKeyDto("c", "Letters & digits", ["HotkeyKey", "SendToken"], false),
            new HotkeyKeyDto("WheelUp", "Mouse", ["HotkeyKey", "SendToken"], true),
        ],
        new Dictionary<string, string> { ["Esc"] = "Escape" });

    private static IHotkeysApiClient ApiReturning(HotkeyKeyCatalogDto catalog)
    {
        IHotkeysApiClient api = Substitute.For<IHotkeysApiClient>();
        api.GetKeysAsync(Arg.Any<CancellationToken>()).Returns(ApiResult<HotkeyKeyCatalogDto>.Ok(catalog));
        return api;
    }

    private static IHotkeysApiClient ApiBlockingUntil(TaskCompletionSource<HotkeyKeyCatalogDto> tcs)
    {
        IHotkeysApiClient api = Substitute.For<IHotkeysApiClient>();
        api.GetKeysAsync(Arg.Any<CancellationToken>()).Returns(_ => WaitThenOkAsync(tcs));
        return api;
    }

    private static async Task<ApiResult<HotkeyKeyCatalogDto>> WaitThenOkAsync(TaskCompletionSource<HotkeyKeyCatalogDto> tcs)
    {
        HotkeyKeyCatalogDto catalog = await tcs.Task;
        return ApiResult<HotkeyKeyCatalogDto>.Ok(catalog);
    }

    [Fact]
    public async Task ForRoleAsync_ReturnsOnlyKeysCarryingThatRole()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));

        IReadOnlyList<HotkeyKeyDto> remapDests = await catalog.ForRoleAsync("RemapDest", CancellationToken.None);

        remapDests.Should().ContainSingle().Which.Canonical.Should().Be("F1");
    }

    [Fact]
    public async Task ForRoleAsync_FetchesOnceAcrossRepeatedCalls()
    {
        IHotkeysApiClient api = ApiReturning(Sample);
        var catalog = new HotkeyKeyCatalog(api);

        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);
        await catalog.ForRoleAsync("SendToken", CancellationToken.None);

        await api.Received(1).GetKeysAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task GroupOf_ReturnsTheEntrysPickerGroup()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.GroupOf("F1").Should().Be("Function keys");
        catalog.GroupOf("WheelUp").Should().Be("Mouse");
        catalog.GroupOf("vk1B").Should().BeNull();
    }

    [Fact]
    public async Task RequiresBracesInSend_ReadsTheRegistryFlag()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("SendToken", CancellationToken.None);

        catalog.RequiresBracesInSend("F1").Should().BeTrue();
        catalog.RequiresBracesInSend("c").Should().BeFalse();

        // Not a registry name: vk/sc codes must still be braced inside a Send token.
        catalog.RequiresBracesInSend("vk1B").Should().BeTrue();
    }

    [Theory]
    [InlineData("F1")]
    [InlineData("f1")]
    [InlineData("Esc")]
    [InlineData("esc")]
    [InlineData("vk1B")]
    [InlineData("sc001")]
    public async Task IsValidKey_AcceptsRegistryAliasAndCodes(string key)
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.IsValidKey(key).Should().BeTrue();
    }

    [Theory]
    [InlineData("zzz")]
    [InlineData("vk00")]
    [InlineData("sc000")]
    [InlineData("vk1Bsc001")]
    [InlineData("")]
    [InlineData(null)]
    public async Task IsValidKey_RejectsUnknownZeroAndCombinedCodes(string? key)
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));
        await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.IsValidKey(key).Should().BeFalse();
    }

    [Fact]
    public void IsValidKey_BeforeLoad_IsOptimistic()
    {
        var catalog = new HotkeyKeyCatalog(ApiReturning(Sample));

        catalog.IsValidKey("anything at all").Should().BeTrue();
    }

    [Fact]
    public async Task ForRoleAsync_RacingCalls_FetchesOnlyOnce()
    {
        var tcs = new TaskCompletionSource<HotkeyKeyCatalogDto>();
        IHotkeysApiClient api = ApiBlockingUntil(tcs);
        var catalog = new HotkeyKeyCatalog(api);

        // Both calls must enter LoadAsync's pre-lock check before either fetch completes, so
        // the second finds the gate held rather than short-circuiting on the outer null check.
        Task<IReadOnlyList<HotkeyKeyDto>> first = catalog.ForRoleAsync("HotkeyKey", CancellationToken.None).AsTask();
        Task<IReadOnlyList<HotkeyKeyDto>> second = catalog.ForRoleAsync("HotkeyKey", CancellationToken.None).AsTask();
        tcs.SetResult(Sample);
        await Task.WhenAll(first, second);

        await api.Received(1).GetKeysAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ForRoleAsync_FailedFetch_IsNotCachedAndRetriedOnNextCall()
    {
        IHotkeysApiClient api = Substitute.For<IHotkeysApiClient>();
        api.GetKeysAsync(Arg.Any<CancellationToken>())
            .Returns(
                ApiResult<HotkeyKeyCatalogDto>.Failure(ApiResultStatus.ServerError, null),
                ApiResult<HotkeyKeyCatalogDto>.Ok(Sample));
        var catalog = new HotkeyKeyCatalog(api);

        IReadOnlyList<HotkeyKeyDto> afterFailure = await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        catalog.IsLoaded.Should().BeFalse();
        afterFailure.Should().BeEmpty();

        IReadOnlyList<HotkeyKeyDto> afterRetry = await catalog.ForRoleAsync("HotkeyKey", CancellationToken.None);

        afterRetry.Should().NotBeEmpty();
        catalog.IsLoaded.Should().BeTrue();
        await api.Received(2).GetKeysAsync(Arg.Any<CancellationToken>());
    }
}
