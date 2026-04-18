using AHKFlowApp.UI.Blazor.Auth;
using AHKFlowApp.UI.Blazor.Services;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();

builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");

string[] requiredConfigKeys = [
    "ApiHttpClient:BaseAddress",
    "AzureAd:Authority",
    "AzureAd:ClientId",
    "AzureAd:DefaultScope"
];
foreach (string key in requiredConfigKeys)
{
    if (string.IsNullOrWhiteSpace(builder.Configuration[key]))
    {
        throw new InvalidOperationException($"Configuration value '{key}' is missing or empty.");
    }
}

string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]!;
string defaultScope = builder.Configuration["AzureAd:DefaultScope"]!;

builder.Services.AddMsalAuthentication(options =>
{
    builder.Configuration.Bind("AzureAd", options.ProviderOptions.Authentication);
    options.ProviderOptions.DefaultAccessTokenScopes.Add(defaultScope);
    options.ProviderOptions.LoginMode = "redirect";
});

builder.Services.AddTransient<ApiAuthorizationMessageHandler>();

builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
})
    .AddHttpMessageHandler<ApiAuthorizationMessageHandler>()
    .AddStandardResilienceHandler();

builder.Services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
})
    .AddHttpMessageHandler<ApiAuthorizationMessageHandler>()
    .AddStandardResilienceHandler();

await builder.Build().RunAsync();
