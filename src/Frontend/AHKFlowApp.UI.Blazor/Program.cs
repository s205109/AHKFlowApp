using AHKFlowApp.UI.Blazor.Auth;
using AHKFlowApp.UI.Blazor.Services;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Microsoft.Extensions.Http.Resilience;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();
builder.Services.AddScoped<LocalStorageUserPreferencesService>();
builder.Services.AddScoped<IUserPreferencesService, HybridUserPreferencesService>();

builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");

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

    if (configureResilience is not null)
    {
        clientBuilder.AddStandardResilienceHandler(configureResilience);
    }
    else
    {
        clientBuilder.AddStandardResilienceHandler();
    }
}

Action<HttpStandardResilienceOptions> mainClientResilience = options =>
{
    options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(32);
    options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(30);
    options.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
};

bool useTestAuth = builder.Configuration.GetValue<bool>("Auth:UseTestProvider");

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
    AddApiClient<IPreferencesApiClient, PreferencesApiClient>(
        baseAddress, TimeSpan.FromSeconds(10), useAuth: false);
}
else
{
    AuthConfigurationValidator.ValidateForMsal(builder.Configuration);

    string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]!;
    string defaultScope = builder.Configuration["AzureAd:DefaultScope"]!;
    Uri baseAddress = new(apiBaseUrl);

    builder.Services.AddMsalAuthentication(options =>
    {
        builder.Configuration.Bind("AzureAd", options.ProviderOptions.Authentication);
        options.ProviderOptions.DefaultAccessTokenScopes.Add(defaultScope);
        options.ProviderOptions.LoginMode = "redirect";
    });

    builder.Services.AddTransient<ApiAuthorizationMessageHandler>();

    AddApiClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(
        baseAddress, TimeSpan.FromSeconds(35), useAuth: true, mainClientResilience);
    AddApiClient<IHotstringsApiClient, HotstringsApiClient>(
        baseAddress, TimeSpan.FromSeconds(30), useAuth: true);
    AddApiClient<IPreferencesApiClient, PreferencesApiClient>(
        baseAddress, TimeSpan.FromSeconds(10), useAuth: true);
}

await builder.Build().RunAsync();
