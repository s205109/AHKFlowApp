using System.Text.Json;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Fixtures;

public sealed class TestTimingRecorderTests : IDisposable
{
    private readonly string _timingDirectory = Path.Combine(Path.GetTempPath(), $"ahkflow-test-timing-{Guid.NewGuid():N}");

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("AHKFLOW_TEST_TIMING", null);
        Environment.SetEnvironmentVariable("AHKFLOW_TEST_TIMING_DIR", null);

        if (Directory.Exists(_timingDirectory))
        {
            Directory.Delete(_timingDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task RecordAsync_TimingEnabled_WritesMachineReadableEntry()
    {
        // Arrange
        Environment.SetEnvironmentVariable("AHKFLOW_TEST_TIMING", "1");
        Environment.SetEnvironmentVariable("AHKFLOW_TEST_TIMING_DIR", _timingDirectory);

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
        Environment.SetEnvironmentVariable("AHKFLOW_TEST_TIMING", null);
        Environment.SetEnvironmentVariable("AHKFLOW_TEST_TIMING_DIR", _timingDirectory);

        // Act
        await TestTimingRecorder.RecordAsync(
            "TestTimingRecorder",
            "AHKFlowApp.TestUtilities.Fixtures.TestTimingRecorder",
            "RecordAsync",
            () => Task.CompletedTask);

        // Assert
        Directory.Exists(_timingDirectory).Should().BeFalse();
    }
}
