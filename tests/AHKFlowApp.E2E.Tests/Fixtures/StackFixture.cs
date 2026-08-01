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
        await db.CustomKnownShortcuts.ExecuteDeleteAsync();
        await db.IgnoredKnownShortcuts.ExecuteDeleteAsync();
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

    public string PublishedWwwroot { get; } = ResolvePublishedWwwroot();

    public static string ResolveConfiguration() =>
        new DirectoryInfo(AppContext.BaseDirectory).Parent?.Name ?? "Release";

    public static string ResolvePublishedWwwroot()
    {
        var testOutputDirectory = new DirectoryInfo(AppContext.BaseDirectory);
        string targetFramework = testOutputDirectory.Name;

        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", "..",
            "src", "Frontend", "AHKFlowApp.UI.Blazor", "bin", ResolveConfiguration(), targetFramework, "publish", "wwwroot"));
    }

    private async Task InitializeCoreAsync()
    {
        await Api.StartAsync();

        if (!Directory.Exists(PublishedWwwroot))
        {
            throw new DirectoryNotFoundException($"Publish wwwroot not found at {PublishedWwwroot}. Run: dotnet publish src/Frontend/AHKFlowApp.UI.Blazor -c {ResolveConfiguration()}");
        }

        HttpMessageInvoker apiClient = new(Api.Server.CreateHandler());
        Spa = await SpaHost.StartAsync(PublishedWwwroot, apiClient, Api.Server.BaseAddress.ToString());

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
