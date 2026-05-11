using System.Runtime.InteropServices;
using AHKFlowApp.CLI.Exceptions;
using Microsoft.Extensions.Options;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Extensions.Msal;

namespace AHKFlowApp.CLI.Services;

public sealed class MsalDeviceCodeTokenProvider(
    IOptions<CliOptions> options,
    IDeviceCodePromptWriter promptWriter,
    IAuthCachePathProvider cachePathProvider) : IAuthTokenProvider
{
    private IPublicClientApplication? _app;
    private string[]? _scopes;
    private string? _cacheFilePath;

    public async Task<string> GetTokenAsync(CancellationToken ct)
    {
        IPublicClientApplication app = await GetAppAsync(ct);
        IAccount? account = (await app.GetAccountsAsync()).FirstOrDefault();
        if (account is null)
        {
            throw new NotAuthenticatedException(AuthMessages.LoginRequired);
        }

        try
        {
            AuthenticationResult result = await app
                .AcquireTokenSilent(_scopes!, account)
                .ExecuteAsync(ct);
            return result.AccessToken;
        }
        catch (MsalUiRequiredException)
        {
            throw new NotAuthenticatedException(AuthMessages.LoginRequired);
        }
    }

    public async Task<LoginResult> LoginAsync(CancellationToken ct)
    {
        IPublicClientApplication app = await GetAppAsync(ct);
        IAccount? account = (await app.GetAccountsAsync()).FirstOrDefault();
        if (account is not null)
        {
            try
            {
                AuthenticationResult silent = await app
                    .AcquireTokenSilent(_scopes!, account)
                    .ExecuteAsync(ct);
                return new LoginResult(silent.Account.Username, true);
            }
            catch (MsalUiRequiredException)
            {
            }
        }

        AuthenticationResult interactive = await app
            .AcquireTokenWithDeviceCode(_scopes!, async code =>
            {
                await promptWriter.WriteAsync(
                    new DeviceCodePrompt(
                        code.VerificationUrl,
                        code.UserCode,
                        code.Message),
                    ct);
            })
            .ExecuteAsync(ct);

        return new LoginResult(interactive.Account.Username, false);
    }

    public async Task LogoutAsync(CancellationToken ct)
    {
        IPublicClientApplication app = await GetAppAsync(ct);
        foreach (IAccount account in await app.GetAccountsAsync())
        {
            await app.RemoveAsync(account);
        }

        TryDeleteCacheFile();
    }

    private async Task<IPublicClientApplication> GetAppAsync(CancellationToken ct)
    {
        if (_app is not null)
        {
            return _app;
        }

        CliOptions config = options.Value;
        Guid clientId = ParseRequiredGuid(config.ClientId, nameof(config.ClientId));
        Guid tenantId = ParseRequiredGuid(config.TenantId, nameof(config.TenantId));

        _scopes = [$"api://{clientId}/access_as_user"];
        _cacheFilePath = cachePathProvider.GetCacheFilePath();

        _app = PublicClientApplicationBuilder
            .Create(clientId.ToString())
            .WithAuthority(AzureCloudInstance.AzurePublic, tenantId)
            .WithRedirectUri("http://localhost")
            .Build();

        var storageBuilder = new StorageCreationPropertiesBuilder(
            Path.GetFileName(_cacheFilePath),
            Path.GetDirectoryName(_cacheFilePath)!);

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            storageBuilder.WithLinuxKeyring(
                schemaName: "com.ahkflowapp.cli.tokencache",
                collection: MsalCacheHelper.LinuxKeyRingDefaultCollection,
                secretLabel: "AHKFlowApp CLI Token Cache",
                attribute1: new KeyValuePair<string, string>("Version", "1"),
                attribute2: new KeyValuePair<string, string>("ProductGroup", "AHKFlowApp"));
        }

        StorageCreationProperties storageProperties = storageBuilder.Build();

        MsalCacheHelper cacheHelper = await MsalCacheHelper
            .CreateAsync(storageProperties)
            .WaitAsync(ct);
        cacheHelper.RegisterCache(_app.UserTokenCache);

        return _app;
    }

    private static Guid ParseRequiredGuid(string value, string key)
    {
        if (!Guid.TryParse(value, out Guid parsed) || parsed == Guid.Empty)
        {
            throw new AuthConfigurationException($"{key} is not configured.");
        }

        return parsed;
    }

    private void TryDeleteCacheFile()
    {
        if (_cacheFilePath is null)
        {
            return;
        }

        try
        {
            File.Delete(_cacheFilePath);
        }
        catch (Exception ex) when (ex is FileNotFoundException or IOException or UnauthorizedAccessException)
        {
        }
    }
}
