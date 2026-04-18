using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class StackFixture : IAsyncLifetime
{
    public ApiFactory Api { get; } = new();
    public SpaHost Spa { get; private set; } = default!;
    public IPlaywright Playwright { get; private set; } = default!;
    public IBrowser Browser { get; private set; } = default!;

    public async Task InitializeAsync()
    {
        await Api.StartAsync();

        string wwwroot = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", "..",
            "src", "Frontend", "AHKFlowApp.UI.Blazor", "bin", "Release", "net10.0", "publish", "wwwroot"));

        if (!Directory.Exists(wwwroot))
            throw new DirectoryNotFoundException($"Publish wwwroot not found at {wwwroot}. Run: dotnet publish src/Frontend/AHKFlowApp.UI.Blazor -c Release");

        HttpMessageInvoker apiClient = new(Api.Server.CreateHandler());
        Spa = await SpaHost.StartAsync(wwwroot, apiClient, Api.Server.BaseAddress.ToString());

        Microsoft.Playwright.Program.Main(["install", "chromium"]);
        Playwright = await Microsoft.Playwright.Playwright.CreateAsync();
        Browser = await Playwright.Chromium.LaunchAsync(new() { Headless = true });
    }

    public async Task DisposeAsync()
    {
        await Browser.CloseAsync();
        Playwright.Dispose();
        await Spa.DisposeAsync();
        await Api.DisposeAsync();
    }
}
