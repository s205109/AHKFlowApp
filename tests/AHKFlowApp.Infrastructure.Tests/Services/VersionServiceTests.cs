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
}
