using AHKFlowApp.UI.Blazor.Services;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddMudServices();

builder.RootComponents.Add<AHKFlowApp.UI.Blazor.App>("#app");

string apiBaseUrl = builder.Configuration["ApiHttpClient:BaseAddress"]
    ?? throw new InvalidOperationException("ApiHttpClient:BaseAddress is not configured.");

builder.Services.AddHttpClient<IAhkFlowAppApiHttpClient, AhkFlowAppApiHttpClient>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
}).AddStandardResilienceHandler();

await builder.Build().RunAsync();
