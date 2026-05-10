using AHKFlowApp.CLI;
using AHKFlowApp.CLI.Exceptions;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Microsoft.Extensions.Options;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class MsalDeviceCodeTokenProviderTests : IDisposable
{
    private readonly string _tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task GetTokenAsync_InvalidClientId_ThrowsAuthConfigurationException()
    {
        MsalDeviceCodeTokenProvider sut = CreateProvider(new CliOptions
        {
            ClientId = "",
            TenantId = Guid.NewGuid().ToString(),
        });

        Func<Task> act = () => sut.GetTokenAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<AuthConfigurationException>())
            .WithMessage("ClientId is not configured.");
    }

    [Fact]
    public async Task LoginAsync_InvalidTenantId_ThrowsAuthConfigurationException()
    {
        MsalDeviceCodeTokenProvider sut = CreateProvider(new CliOptions
        {
            ClientId = Guid.NewGuid().ToString(),
            TenantId = "00000000-0000-0000-0000-000000000000",
        });

        Func<Task> act = () => sut.LoginAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<AuthConfigurationException>())
            .WithMessage("TenantId is not configured.");
    }

    [Fact]
    public async Task GetTokenAsync_NoCachedAccount_ThrowsNotAuthenticated()
    {
        MsalDeviceCodeTokenProvider sut = CreateProvider(new CliOptions
        {
            ClientId = Guid.NewGuid().ToString(),
            TenantId = Guid.NewGuid().ToString(),
        });

        Func<Task> act = () => sut.GetTokenAsync(CancellationToken.None);

        (await act.Should().ThrowAsync<NotAuthenticatedException>())
            .WithMessage(AuthMessages.LoginRequired);
    }

    [Fact]
    public async Task LogoutAsync_NoCacheFile_DoesNotThrow()
    {
        MsalDeviceCodeTokenProvider sut = CreateProvider(new CliOptions
        {
            ClientId = Guid.NewGuid().ToString(),
            TenantId = Guid.NewGuid().ToString(),
        });

        Func<Task> act = () => sut.LogoutAsync(CancellationToken.None);

        await act.Should().NotThrowAsync();
    }

    private MsalDeviceCodeTokenProvider CreateProvider(CliOptions options)
    {
        Directory.CreateDirectory(_tempDir);
        IAuthCachePathProvider cache = Substitute.For<IAuthCachePathProvider>();
        cache.GetCacheFilePath().Returns(Path.Combine(_tempDir, "msal-cache.bin3"));

        return new MsalDeviceCodeTokenProvider(
            Options.Create(options),
            Substitute.For<IDeviceCodePromptWriter>(),
            cache);
    }
}
