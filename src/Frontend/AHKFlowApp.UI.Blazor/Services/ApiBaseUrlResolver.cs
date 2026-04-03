namespace AHKFlowApp.UI.Blazor.Services;

public sealed class ApiBaseUrlResolver
{
    /// <summary>
    /// Default API endpoint candidates matching Backend launchSettings.json profiles:
    /// - https://localhost:7600 - "https + Docker SQL (Recommended)" / "https + LocalDB SQL" (HTTPS)
    /// - http://localhost:5600  - same profiles (HTTP)
    /// - http://localhost:5602  - "Docker Compose (No Debugging)" profile
    /// - http://localhost:5604  - "Docker (API only)" profile
    /// </summary>
    private static readonly string[] s_defaultCandidates =
    [
        "https://localhost:7600",
        "http://localhost:5600",
        "http://localhost:5602",
        "http://localhost:5604"
    ];

    public static async Task<string> ResolveAsync(
        string hostBaseAddress,
        string? configuredBaseAddress,
        string[]? configuredCandidates,
        CancellationToken cancellationToken = default)
    {
        Console.WriteLine("Starting API endpoint auto-detection...");

        List<string> candidates = BuildCandidates(configuredBaseAddress, configuredCandidates);
        List<string> orderedCandidates = OrderByPreferredScheme(candidates, hostBaseAddress);

        Console.WriteLine($"Trying {orderedCandidates.Count} API candidates in priority order...");

        foreach (string candidate in orderedCandidates)
        {
            Console.WriteLine($"Probing API endpoint: {candidate}");
            (bool reachable, string? reason) = await CanReachApiAsync(candidate, cancellationToken);

            if (reachable)
            {
                Console.WriteLine($"✓ API endpoint reachable: {candidate} ({reason})");
                return candidate;
            }

            Console.WriteLine($"✗ API endpoint unreachable: {candidate} - {reason}");
        }

        string fallback = orderedCandidates[0];
        Console.WriteLine($"No API endpoints reachable, falling back to: {fallback}");
        return fallback;
    }

    private static List<string> BuildCandidates(string? configuredBaseAddress, string[]? configuredCandidates)
    {
        var candidates = (configuredCandidates is { Length: > 0 } ? configuredCandidates : s_defaultCandidates)
            .Where(static value => !string.IsNullOrWhiteSpace(value))
            .Select(static value => Normalize(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (!string.IsNullOrWhiteSpace(configuredBaseAddress))
        {
            string preferred = Normalize(configuredBaseAddress);
            candidates.RemoveAll(value => string.Equals(value, preferred, StringComparison.OrdinalIgnoreCase));
            candidates.Insert(0, preferred);
        }

        return candidates;
    }

    private static List<string> OrderByPreferredScheme(List<string> candidates, string hostBaseAddress)
    {
        string hostScheme = GetScheme(hostBaseAddress);

        return [.. candidates.OrderByDescending(value => string.Equals(GetScheme(value), hostScheme, StringComparison.OrdinalIgnoreCase))];
    }

    private static async Task<(bool Reachable, string Reason)> CanReachApiAsync(string baseAddress, CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(baseAddress, UriKind.Absolute, out Uri? uri))
        {
            return (false, "Invalid base address");
        }

        using var probeClient = new HttpClient
        {
            BaseAddress = uri,
            Timeout = TimeSpan.FromSeconds(2)
        };

        try
        {
            using HttpResponseMessage response = await probeClient.GetAsync("/api/v1/health", HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            // Any HTTP response means host/port is reachable.
            return (true, $"HTTP {(int)response.StatusCode}");
        }
        catch (HttpRequestException ex)
        {
            return (false, ex.Message);
        }
        catch (TaskCanceledException)
        {
            return (false, "Timeout");
        }
        catch (Exception ex)
        {
            return (false, $"{ex.GetType().Name}: {ex.Message}");
        }
    }

    private static string Normalize(string value)
    {
        return value.Trim().TrimEnd('/');
    }

    private static string GetScheme(string value)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out Uri? uri)
            ? uri.Scheme
            : string.Empty;
    }
}
