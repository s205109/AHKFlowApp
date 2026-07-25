using AHKFlowApp.UI.Blazor.Auth;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Startup;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Microsoft.Extensions.Http.Resilience;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<HeadOutlet>("head::after");

// CreateDefault fetches appsettings*.json through the browser HTTP cache, which can serve a stale
// response (notably a cached 404 for a previously-missing appsettings.Development.json). Re-read them
// cache-busted in Development and overlay them so a freshly restored/edited file is picked up on
// reload — this is what lets StartupErrorRoot's auto-recovery succeed. Later providers win, so these
// override the cached copies for both validation and MSAL.
if (builder.HostEnvironment.IsDevelopment())
{
    // This await blocks before RunAsync, so nothing is mounted and the Blazor boot indicator is
    // frozen at ~99% for its whole duration. AddCacheBustedDevConfigAsync bounds each fetch with a
    // cancellation token — a slow or restarting dev host used to park the app there indefinitely.
    using HttpClient configHttp = new() { BaseAddress = new Uri(builder.HostEnvironment.BaseAddress) };
    await builder.Configuration.AddCacheBustedDevConfigAsync(configHttp);
}

bool useTestAuth = builder.Configuration.GetValue<bool>("Auth:UseTestProvider");

// Validate required config before wiring any auth-dependent services. On failure, boot a
// friendly error page (with only the minimal services it needs) instead of crashing the app
// into a blank screen.
if (!useTestAuth)
{
    StartupErrorReason? startupConfigError = StartupConfigValidator.Check(builder.Configuration);
    if (startupConfigError is not null)
    {
        builder.Services.AddSingleton(new StartupErrorState(startupConfigError.Value));
        // Lightweight client so StartupErrorRoot can poll the config files and auto-recover once
        // the user restores appsettings.Development.json (no auth/resilience needed).
        builder.Services.AddScoped(_ => new HttpClient { BaseAddress = new Uri(builder.HostEnvironment.BaseAddress) });
        builder.RootComponents.Add<StartupErrorRoot>("#app");
        await builder.Build().RunAsync();
        return;
    }
}

builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");

builder.Services.AddMudServices();
builder.Services.AddScoped<IFileSaver, JsFileSaver>();
builder.Services.AddScoped<LocalStorageUserPreferencesService>();
builder.Services.AddScoped<IUserPreferencesService, HybridUserPreferencesService>();

// Lightweight, auth-free, no-resilience client used by RequireApiConnectivity to probe /health.
builder.Services.AddHttpClient(RequireApiConnectivity.ProbeClientName, client =>
{
    string probeBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"] ?? "/";
    client.BaseAddress = new Uri(probeBaseUrl.EndsWith('/') ? probeBaseUrl : probeBaseUrl + "/");
    client.Timeout = TimeSpan.FromSeconds(3);
});
builder.Services.AddHttpClient<IChangelogClient, ChangelogClient>(client =>
{
    client.BaseAddress = new Uri(builder.HostEnvironment.BaseAddress);
    client.Timeout = TimeSpan.FromSeconds(10);
}).AddStandardResilienceHandler();

void AddApiClient<TInterface, TImpl>(
    Uri baseAddress,
    TimeSpan timeout,
    bool useAuth,
    Action<HttpStandardResilienceOptions>? configureResilience = null)
    where TInterface : class
    where TImpl : class, TInterface
{
    IHttpClientBuilder clientBuilder = builder.Services.AddHttpClient<TInterface, TImpl>(client =>
    {
        client.BaseAddress = baseAddress;
        client.Timeout = timeout;
    });

    if (useAuth)
    {
        clientBuilder.AddHttpMessageHandler<ApiAuthorizationMessageHandler>();
    }

    clientBuilder.AddStandardResilienceHandler(options =>
    {
        configureResilience?.Invoke(options);

        // Must run last: DisableFor wraps the ShouldHandle captured at call time, so any
        // caller that replaces ShouldHandle afterwards would drop the method check.
        options.Retry.DisableForUnsafeHttpMethods();
    });
}

Action<HttpStandardResilienceOptions> mainClientResilience = options =>
{
    options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(32);
    options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(30);
    options.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
};

if (useTestAuth)
{
    string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"] ?? "/";
    Uri baseAddress = new(new Uri(builder.HostEnvironment.BaseAddress), apiBaseUrl);

    builder.Services.AddAuthorizationCore();
    builder.Services.AddScoped<AuthenticationStateProvider, TestAuthenticationProvider>();

    AddApiClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(
        baseAddress, TimeSpan.FromSeconds(35), useAuth: false, mainClientResilience);
    AddApiClient<IHotstringsApiClient, HotstringsApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: false);
    AddApiClient<IHotkeysApiClient, HotkeysApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: false);
    AddApiClient<IProfilesApiClient, ProfilesApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: false);
    AddApiClient<IDashboardApiClient, DashboardApiClient>(
        baseAddress, TimeSpan.FromSeconds(15), useAuth: false);
    AddApiClient<IDownloadsApiClient, DownloadsApiClient>(
        baseAddress, TimeSpan.FromSeconds(60), useAuth: false);
    AddApiClient<IPreferencesApiClient, PreferencesApiClient>(
        baseAddress, TimeSpan.FromSeconds(10), useAuth: false);
    AddApiClient<ICategoriesApiClient, CategoriesApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: false);
}
else
{
    var azureAd = AzureAdSettings.Resolve(builder.Configuration);
    string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]!;
    Uri baseAddress = new(apiBaseUrl);

    builder.Services.AddMsalAuthentication(options =>
    {
        options.ProviderOptions.Authentication.Authority = azureAd.Authority;
        options.ProviderOptions.Authentication.ClientId = azureAd.ClientId;
        options.ProviderOptions.Authentication.ValidateAuthority = azureAd.ValidateAuthority;
        options.ProviderOptions.DefaultAccessTokenScopes.Add(azureAd.Scope);
        options.ProviderOptions.LoginMode = "redirect";
    });

    builder.Services.AddTransient<ApiAuthorizationMessageHandler>();

    AddApiClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(
        baseAddress, TimeSpan.FromSeconds(35), useAuth: true, mainClientResilience);
    AddApiClient<IHotstringsApiClient, HotstringsApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: true);
    AddApiClient<IHotkeysApiClient, HotkeysApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: true);
    AddApiClient<IProfilesApiClient, ProfilesApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: true);
    AddApiClient<IDashboardApiClient, DashboardApiClient>(
        baseAddress, TimeSpan.FromSeconds(15), useAuth: true);
    AddApiClient<IDownloadsApiClient, DownloadsApiClient>(
        baseAddress, TimeSpan.FromSeconds(60), useAuth: true);
    AddApiClient<IPreferencesApiClient, PreferencesApiClient>(
        baseAddress, TimeSpan.FromSeconds(10), useAuth: true);
    AddApiClient<ICategoriesApiClient, CategoriesApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: true);
}

builder.Services.AddScoped<IHotkeyKeyCatalog, HotkeyKeyCatalog>();

await builder.Build().RunAsync();
