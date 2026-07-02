using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class StackFixture : IAsyncLifetime
{
    public ApiFactory Api { get; } = new();
    public SpaHost Spa { get; private set; } = default!;
    public IPlaywright Playwright { get; private set; } = default!;
    public IBrowser Browser { get; private set; } = default!;

    public Task ResetDataAsync() => TestTimingRecorder.RecordAsync(
        nameof(StackFixture),
        typeof(StackFixture).FullName ?? nameof(StackFixture),
        nameof(ResetDataAsync),
        ResetDataCoreAsync);

    private async Task ResetDataCoreAsync()
    {
        await using AsyncServiceScope scope = Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        await db.EntityHistories.ExecuteDeleteAsync();
        await db.HotstringCategories.ExecuteDeleteAsync();
        await db.HotkeyCategories.ExecuteDeleteAsync();
        await db.HotstringProfiles.ExecuteDeleteAsync();
        await db.HotkeyProfiles.ExecuteDeleteAsync();
        await db.Hotstrings.ExecuteDeleteAsync();
        await db.Hotkeys.ExecuteDeleteAsync();
        await db.Profiles.ExecuteDeleteAsync();
        await db.Categories.ExecuteDeleteAsync();
        await db.UserPreferences.ExecuteDeleteAsync();
    }

    public Task InitializeAsync() => TestTimingRecorder.RecordAsync(
        nameof(StackFixture),
        typeof(StackFixture).FullName ?? nameof(StackFixture),
        nameof(InitializeAsync),
        InitializeCoreAsync);

    private async Task InitializeCoreAsync()
    {
        await Api.StartAsync();

        var testOutputDirectory = new DirectoryInfo(AppContext.BaseDirectory);
        string targetFramework = testOutputDirectory.Name;
        string configuration = testOutputDirectory.Parent?.Name ?? "Release";

        string wwwroot = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", "..",
            "src", "Frontend", "AHKFlowApp.UI.Blazor", "bin", configuration, targetFramework, "publish", "wwwroot"));

        if (!Directory.Exists(wwwroot))
        {
            throw new DirectoryNotFoundException($"Publish wwwroot not found at {wwwroot}. Run: dotnet publish src/Frontend/AHKFlowApp.UI.Blazor -c {configuration}");
        }

        HttpMessageInvoker apiClient = new(Api.Server.CreateHandler());
        Spa = await SpaHost.StartAsync(wwwroot, apiClient, Api.Server.BaseAddress.ToString());

        int exitCode = Microsoft.Playwright.Program.Main(["install", "chromium"]);
        if (exitCode != 0)
            throw new InvalidOperationException($"Playwright browser installation failed (exit {exitCode}).");
        Playwright = await Microsoft.Playwright.Playwright.CreateAsync();
        Browser = await Playwright.Chromium.LaunchAsync(new() { Headless = true });
    }

    public async Task DisposeAsync()
    {
        if (Browser is not null) await Browser.CloseAsync();
        Playwright?.Dispose();
        if (Spa is not null) await Spa.DisposeAsync();
        await Api.DisposeAsync();
    }
}
