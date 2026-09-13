using System.Text.Json;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.TestUtilities.Tests.Fixtures;

[Collection(TestCollections.EnvironmentVariables)]
public sealed class TestTimingRecorderTests : IDisposable
{
    private const string TimingEnabledEnvironmentVariable = "AHKFLOW_TEST_TIMING";
    private const string TimingDirectoryEnvironmentVariable = "AHKFLOW_TEST_TIMING_DIR";

    private readonly string _timingDirectory = Path.Combine(Path.GetTempPath(), $"ahkflow-test-timing-{Guid.NewGuid():N}");
    private readonly string? _previousTiming = Environment.GetEnvironmentVariable(TimingEnabledEnvironmentVariable);
    private readonly string? _previousTimingDirectory = Environment.GetEnvironmentVariable(TimingDirectoryEnvironmentVariable);

    public void Dispose()
    {
        Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, _previousTiming);
        Environment.SetEnvironmentVariable(TimingDirectoryEnvironmentVariable, _previousTimingDirectory);

        if (Directory.Exists(_timingDirectory))
        {
            Directory.Delete(_timingDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task RecordAsync_TimingEnabled_WritesMachineReadableEntry()
    {
        // Arrange
        Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, "1");
        Environment.SetEnvironmentVariable(TimingDirectoryEnvironmentVariable, _timingDirectory);

        // Act
        await TestTimingRecorder.RecordAsync(
            "TestTimingRecorder",
            "AHKFlowApp.TestUtilities.Fixtures.TestTimingRecorder",
            "RecordAsync",
            () => Task.Delay(1));

        // Assert
        string timingFile = Directory.GetFiles(_timingDirectory, "fixture-timings-*.jsonl").Should().ContainSingle().Subject;
        JsonElement timingEntry = JsonSerializer.Deserialize<JsonElement>(await File.ReadAllTextAsync(timingFile));

        timingEntry.GetProperty("component").GetString().Should().Be("TestTimingRecorder");
        timingEntry.GetProperty("fixture").GetString().Should().Be("AHKFlowApp.TestUtilities.Fixtures.TestTimingRecorder");
        timingEntry.GetProperty("operation").GetString().Should().Be("RecordAsync");
        timingEntry.GetProperty("elapsedMilliseconds").GetDouble().Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task RecordAsync_TimingDisabled_DoesNotWriteEntry()
    {
        // Arrange
        Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, null);
        Environment.SetEnvironmentVariable(TimingDirectoryEnvironmentVariable, _timingDirectory);

        // Act
        await TestTimingRecorder.RecordAsync(
            "TestTimingRecorder",
            "AHKFlowApp.TestUtilities.Fixtures.TestTimingRecorder",
            "RecordAsync",
            () => Task.CompletedTask);

        // Assert
        Directory.Exists(_timingDirectory).Should().BeFalse();
    }

    [Fact]
    public async Task RecordAsync_TimingEnabled_WritesAnIntervalThatMatchesTheElapsedFigure()
    {
        // Arrange
        Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, "1");
        Environment.SetEnvironmentVariable(TimingDirectoryEnvironmentVariable, _timingDirectory);
        DateTimeOffset before = DateTimeOffset.UtcNow;

        // Act
        await TestTimingRecorder.RecordAsync(
            "TestTimingRecorder",
            "AHKFlowApp.TestUtilities.Fixtures.TestTimingRecorder",
            "RecordAsync",
            () => Task.Delay(20));

        // Assert
        DateTimeOffset after = DateTimeOffset.UtcNow;
        string timingFile = Directory.GetFiles(_timingDirectory, "fixture-timings-*.jsonl").Should().ContainSingle().Subject;
        JsonElement timingEntry = JsonSerializer.Deserialize<JsonElement>(await File.ReadAllTextAsync(timingFile));

        DateTimeOffset startedUtc = timingEntry.GetProperty("startedUtc").GetDateTimeOffset();
        DateTimeOffset finishedUtc = timingEntry.GetProperty("finishedUtc").GetDateTimeOffset();
        double elapsedMilliseconds = timingEntry.GetProperty("elapsedMilliseconds").GetDouble();

        startedUtc.Should().BeOnOrAfter(before, "the interval cannot start before the call did");
        finishedUtc.Should().BeOnOrBefore(after, "the interval cannot finish after the call returned");
        finishedUtc.Should().BeOnOrAfter(startedUtc, "an interval never ends before it starts");
        (finishedUtc - startedUtc).TotalMilliseconds.Should().BeApproximately(
            elapsedMilliseconds, 0.001,
            "the interval length is the elapsed figure, so a reader can use either one");
    }

    [Fact]
    public async Task RecordAsync_WithACaller_WritesTheCaller()
    {
        // Arrange
        Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, "1");
        Environment.SetEnvironmentVariable(TimingDirectoryEnvironmentVariable, _timingDirectory);

        // Act
        await TestTimingRecorder.RecordAsync(
            "TestTimingRecorder",
            "AHKFlowApp.TestUtilities.Fixtures.TestTimingRecorder",
            "RecordAsync",
            () => Task.CompletedTask,
            caller: "StackFixture");

        // Assert
        string timingFile = Directory.GetFiles(_timingDirectory, "fixture-timings-*.jsonl").Should().ContainSingle().Subject;
        JsonElement timingEntry = JsonSerializer.Deserialize<JsonElement>(await File.ReadAllTextAsync(timingFile));

        timingEntry.GetProperty("caller").GetString().Should().Be(
            "StackFixture", "the caller is what lets a report separate a stack's own step from a test's");
    }
}
