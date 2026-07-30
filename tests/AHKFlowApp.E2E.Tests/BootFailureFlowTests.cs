using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Guards the boot path in wwwroot/js/bootBlazor.js. Blazor is started manually so a boot
// failure ends in a visible message instead of a loading circle frozen at 99%.
[Collection(E2ETestCollection.Name)]
public sealed class BootFailureFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private const string ReloadGuardKey = "ahkflowapp-boot-retry-reload";

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task SuccessfulBoot_RendersApp_AndClearsReloadGuard()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        // Pre-set the guard so this proves clearing, not just absence. Without the clear,
        // one recovered failure would cost the next unrelated failure its free retry.
        await ctx.AddInitScriptAsync($"sessionStorage.setItem('{ReloadGuardKey}', 'true');");

        IPage page = await ctx.NewPageAsync();
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");

        // The app renders as before: manual start changed nothing on the success path.
        await page.WaitForSelectorAsync("button.add-hotstring");

        string? guard = await page.EvaluateAsync<string?>(
            $"() => sessionStorage.getItem('{ReloadGuardKey}')");
        guard.Should().BeNull();
    }
}
