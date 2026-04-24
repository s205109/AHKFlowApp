using AHKFlowApp.Infrastructure.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Services;

public sealed class VersionServiceTests
{
    [Fact]
    public async Task GetVersionAsync_WhenNotCancelled_ReturnsVersionString()
    {
        var sut = new VersionService();

        string version = await sut.GetVersionAsync(CancellationToken.None);

        version.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task GetVersionAsync_WhenAlreadyCancelled_ThrowsOperationCancelledException()
    {
        var sut = new VersionService();
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        Func<Task> act = async () => await sut.GetVersionAsync(cts.Token);

        await act.Should().ThrowAsync<OperationCanceledException>();
    }
}
