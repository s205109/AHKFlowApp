using System.Runtime.CompilerServices;
using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class NoAuthAppSettingsTests
{
    private static string GetNoAuthAppSettingsPath([CallerFilePath] string testFilePath = "")
    {
        string testDirectory = Path.GetDirectoryName(testFilePath)!;
        return Path.GetFullPath(Path.Combine(
            testDirectory, "..", "..", "..",
            "src", "Frontend", "AHKFlowApp.UI.Blazor", "wwwroot", "appsettings.NoAuth.json"));
    }

    [Fact]
    public void AppSettingsNoAuthJson_Read_DoesNotOverrideApiHttpClientBaseAddress()
    {
        // Blazor WASM loads appsettings.json first, then appsettings.{Environment}.json on top.
        // appsettings.NoAuth.json only needs to turn on Auth:UseTestProvider. If it also sets
        // ApiHttpClient:BaseAddress, that value always wins, even where appsettings.json holds
        // the right address for the current checkout (for example a worktree's own API port).
        // The base file should be the only place that sets the API address.
        string path = GetNoAuthAppSettingsPath();
        string json = File.ReadAllText(path);

        using var document = JsonDocument.Parse(json);

        document.RootElement.TryGetProperty("ApiHttpClient", out _).Should().BeFalse(
            "appsettings.NoAuth.json must not set ApiHttpClient:BaseAddress. " +
            "It layers on top of appsettings.json, so a value here always wins over the base " +
            "file's address, even when the base file already has the right one for this checkout.");
    }
}
