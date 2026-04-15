using AHKFlowApp.UI.Blazor.Services;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Authentication;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();

builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");

string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]
    ?? throw new InvalidOperationException("ApiHttpClient:BaseAddress is not configured.");

builder.Services.AddMsalAuthentication(options =>
{
    builder.Configuration.Bind("AzureAd", options.ProviderOptions.Authentication);
    options.ProviderOptions.DefaultAccessTokenScopes.Add(builder.Configuration["AzureAd:DefaultScope"]!);
    options.ProviderOptions.LoginMode = "redirect";
});

builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
})
    .AddHttpMessageHandler<BaseAddressAuthorizationMessageHandler>()
    .AddStandardResilienceHandler();

await builder.Build().RunAsync();
