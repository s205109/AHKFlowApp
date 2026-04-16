using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Shared;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();

var missingFields = new List<string>();
if (string.IsNullOrWhiteSpace(builder.Configuration["AzureAd:Authority"])) missingFields.Add("Authority");
if (string.IsNullOrWhiteSpace(builder.Configuration["AzureAd:ClientId"])) missingFields.Add("ClientId");
if (string.IsNullOrWhiteSpace(builder.Configuration["AzureAd:DefaultScope"])) missingFields.Add("DefaultScope");

if (missingFields.Count > 0)
{
    builder.Services.AddSingleton<IReadOnlyList<string>>(missingFields);
    builder.RootComponents.Add<ConfigurationError>("#app");
    await builder.Build().RunAsync();
    return;
}

builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");

string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]
    ?? throw new InvalidOperationException("ApiHttpClient:BaseAddress is not configured.");

builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
}).AddStandardResilienceHandler();

await builder.Build().RunAsync();
