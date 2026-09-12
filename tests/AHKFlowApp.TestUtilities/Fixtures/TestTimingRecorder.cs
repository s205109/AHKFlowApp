using System.Diagnostics;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace AHKFlowApp.TestUtilities.Fixtures;

public static class TestTimingRecorder
{
    private static readonly SemaphoreSlim WriteLock = new(1, 1);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <param name="caller">
    /// Who asked for the step, when the component is shared. A component such as the host start
    /// gate serves stack fixtures and tests alike, and without this field a report cannot tell a
    /// stack's own start from a test's. Leave it null for a step only one kind of caller runs.
    /// </param>
    public static async Task RecordAsync(
        string component,
        string fixture,
        string operation,
        Func<Task> action,
        string? caller = null)
    {
        if (!IsEnabled())
        {
            await action();
            return;
        }

        DateTimeOffset startedUtc = DateTimeOffset.UtcNow;
        var stopwatch = Stopwatch.StartNew();
        await action();
        stopwatch.Stop();

        // The stopwatch measures the length and the wall clock anchors it. Deriving the finish
        // from the start plus the elapsed figure keeps the two consistent: a reader who subtracts
        // the interval gets the elapsed figure back exactly, with no second clock reading to drift.
        TimingEntry entry = new(
            TimestampUtc: DateTimeOffset.UtcNow,
            StartedUtc: startedUtc,
            FinishedUtc: startedUtc.AddMilliseconds(stopwatch.Elapsed.TotalMilliseconds),
            TestAssembly: GetTestAssemblyName(),
            ProcessId: Environment.ProcessId,
            Component: component,
            Fixture: fixture,
            Operation: operation,
            ElapsedMilliseconds: stopwatch.Elapsed.TotalMilliseconds,
            Caller: caller);

        await WriteAsync(entry);
    }

    private static bool IsEnabled()
    {
        string? value = Environment.GetEnvironmentVariable("AHKFLOW_TEST_TIMING");
        return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private static async Task WriteAsync(TimingEntry entry)
    {
        string outputDirectory = GetOutputDirectory();
        Directory.CreateDirectory(outputDirectory);

        string outputPath = Path.Combine(outputDirectory, $"fixture-timings-{Environment.ProcessId}.jsonl");
        string jsonLine = JsonSerializer.Serialize(entry, JsonOptions) + Environment.NewLine;

        await WriteLock.WaitAsync();
        try
        {
            await File.AppendAllTextAsync(outputPath, jsonLine, Encoding.UTF8);
        }
        finally
        {
            WriteLock.Release();
        }
    }

    private static string GetOutputDirectory()
    {
        string? configuredDirectory = Environment.GetEnvironmentVariable("AHKFLOW_TEST_TIMING_DIR");
        if (!string.IsNullOrWhiteSpace(configuredDirectory))
        {
            return Path.GetFullPath(configuredDirectory);
        }

        return Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "TestResults", "fixture-timing"));
    }

    private static string GetTestAssemblyName()
    {
        Assembly? testAssembly = AppDomain.CurrentDomain.GetAssemblies()
            .Where(assembly => !assembly.IsDynamic)
            .FirstOrDefault(assembly => assembly.GetName().Name?.EndsWith(".Tests", StringComparison.Ordinal) == true);

        return testAssembly?.GetName().Name ?? AppDomain.CurrentDomain.FriendlyName;
    }

    private sealed record TimingEntry(
        DateTimeOffset TimestampUtc,
        DateTimeOffset StartedUtc,
        DateTimeOffset FinishedUtc,
        string TestAssembly,
        int ProcessId,
        string Component,
        string Fixture,
        string Operation,
        double ElapsedMilliseconds,
        string? Caller);
}
