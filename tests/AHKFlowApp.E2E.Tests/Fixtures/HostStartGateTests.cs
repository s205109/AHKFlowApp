using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// The lifecycle checks the design requires for several API hosts in one process.
/// </summary>
/// <remarks>
/// The first two tests drive <see cref="HostStartGate"/> directly with controlled callbacks, so
/// they fail every time the gate stops working. The two host tests below them cost a real host
/// start each, and they only catch the Serilog race when the timing happens to line up, so they
/// confirm the gate in the real host and never stand in for the deterministic pair.
/// </remarks>
[Collection(ExclusiveTestCollection.Name)]
public sealed class HostStartGateTests : IDisposable
{
    private const string TimingEnabledEnvironmentVariable = "AHKFLOW_TEST_TIMING";
    private const string TimingDirectoryEnvironmentVariable = "AHKFLOW_TEST_TIMING_DIR";

    private static readonly TimeSpan WaitLimit = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan SettleTime = TimeSpan.FromMilliseconds(250);

    private readonly string _timingDirectory = Path.Combine(Path.GetTempPath(), $"ahkflow-gate-timing-{Guid.NewGuid():N}");
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
    public async Task RunAsync_WhileOneCallbackIsRunning_HoldsTheNextCallerBack()
    {
        // Arrange
        TaskCompletionSource firstEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        TaskCompletionSource releaseFirst = new(TaskCreationOptions.RunContinuationsAsynchronously);
        bool secondStarted = false;

        Task first = HostStartGate.RunAsync(async () =>
        {
            firstEntered.SetResult();
            await releaseFirst.Task;
        });

        try
        {
            await firstEntered.Task.WaitAsync(WaitLimit);

            // Act
            Task second = HostStartGate.RunAsync(() =>
            {
                secondStarted = true;
                return Task.CompletedTask;
            });

            await Task.Delay(SettleTime);

            // Assert
            secondStarted.Should().BeFalse(
                "the second host must wait while the first one holds the gate");
            second.IsCompleted.Should().BeFalse("the second caller is still waiting for the gate");

            releaseFirst.SetResult();
            await second.WaitAsync(WaitLimit);
            secondStarted.Should().BeTrue("the second host runs once the first one releases the gate");
        }
        finally
        {
            releaseFirst.TrySetResult();
            await first;
        }
    }

    [Fact]
    public async Task RunAsync_WhenTheCallbackThrows_StillReleasesTheGate()
    {
        // Arrange
        Func<Task> failing = () => HostStartGate.RunAsync(
            () => throw new InvalidOperationException("host start failed on purpose"));

        // Act
        await failing.Should().ThrowAsync<InvalidOperationException>();

        // Assert
        bool ranAfterTheFailure = false;
        await HostStartGate.RunAsync(() =>
        {
            ranAfterTheFailure = true;
            return Task.CompletedTask;
        }).WaitAsync(WaitLimit);

        ranAfterTheFailure.Should().BeTrue(
            "a host start that throws must not leave the gate closed for every later host");
    }

    [Fact]
    public async Task FourHostsStartedTogether_DoNotFreezeTheSameSerilogLogger()
    {
        for (int round = 0; round < 3; round++)
        {
            ApiFactory[] factories =
            [
                new("AHKFlowApp.E2E.Tests.GateA"),
                new("AHKFlowApp.E2E.Tests.GateB"),
                new("AHKFlowApp.E2E.Tests.GateC"),
                new("AHKFlowApp.E2E.Tests.GateD"),
            ];

            try
            {
                await Task.WhenAll(factories.Select(factory => factory.StartAsync()));
            }
            finally
            {
                foreach (ApiFactory factory in factories)
                {
                    await factory.DisposeAsync();
                }
            }
        }
    }

    [Fact]
    public async Task DisposingOneHost_LeavesTheOthersServing()
    {
        ApiFactory first = new("AHKFlowApp.E2E.Tests.GateE");
        bool firstDisposed = false;
        await using ApiFactory second = new("AHKFlowApp.E2E.Tests.GateF");

        try
        {
            await first.StartAsync();
            await second.StartAsync();

            // Deliberate: the first host closes the shared Serilog logger on its way out.
            await first.DisposeAsync();
            firstDisposed = true;

            using HttpClient client = second.CreateClient();
            using HttpResponseMessage response = await client.GetAsync("/health");

            response.IsSuccessStatusCode.Should().BeTrue(
                "a stack must keep serving after another stack closes the shared Serilog logger");
        }
        finally
        {
            if (!firstDisposed)
            {
                await first.DisposeAsync();
            }
        }
    }

    [Fact]
    public async Task RunAsync_WithFourCallersAtOnce_RecordsWaitingApartFromWork()
    {
        // Arrange
        const int callers = 4;
        var hold = TimeSpan.FromMilliseconds(300);
        EnableTiming(_timingDirectory);

        // Act: release all four at the same moment, so every caller but one has to queue.
        TaskCompletionSource release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        Task[] callersRunning = Enumerable.Range(0, callers)
            .Select(_ => Task.Run(async () =>
            {
                await release.Task;
                await HostStartGate.RunAsync(() => Task.Delay(hold));
            }))
            .ToArray();

        release.SetResult();
        await Task.WhenAll(callersRunning).WaitAsync(WaitLimit);

        // Assert
        List<JsonElement> entries = ReadGateEntries();

        double[] waits = entries
            .Where(entry => entry.GetProperty("operation").GetString() == HostStartGate.QueueWaitOperation)
            .Select(entry => entry.GetProperty("elapsedMilliseconds").GetDouble())
            .ToArray();
        double[] work = entries
            .Where(entry => entry.GetProperty("operation").GetString() == HostStartGate.GatedWorkOperation)
            .Select(entry => entry.GetProperty("elapsedMilliseconds").GetDouble())
            .ToArray();

        waits.Should().HaveCount(callers, "every caller records its own wait");
        work.Should().HaveCount(callers, "every caller records its own gated work");

        work.Should().AllSatisfy(one => one.Should().BeLessThan(
            hold.TotalMilliseconds * 2,
            "gated work is one hold, so no caller may report the queued total"));

        waits.Max().Should().BeGreaterThan(
            hold.TotalMilliseconds * 2,
            "the last caller waited for three holds, and that time is waiting rather than work");
    }

    [Fact]
    public async Task RunAsync_WhenRecordingTheWaitFails_StillReleasesTheGate()
    {
        // Arrange: a file sits where the recorder expects a folder, so the recorder throws while
        // it writes the wait, which is after the wait has already taken the permit.
        string blocker = Path.Combine(Path.GetTempPath(), $"ahkflow-gate-blocker-{Guid.NewGuid():N}");
        await File.WriteAllTextAsync(blocker, "a file where the recorder expects a folder");
        EnableTiming(Path.Combine(blocker, "timing"));

        try
        {
            // Act
            Func<Task> recordingFails = () => HostStartGate.RunAsync(() => Task.CompletedTask);
            await recordingFails.Should().ThrowAsync<IOException>();

            // Assert: timing off, so the next caller cannot fail on the same write for its own reason.
            Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, null);
            bool ranAfterTheFailure = false;
            await HostStartGate.RunAsync(() =>
            {
                ranAfterTheFailure = true;
                return Task.CompletedTask;
            }).WaitAsync(WaitLimit);

            ranAfterTheFailure.Should().BeTrue(
                "a timing record that fails to write must not leave the gate closed for every later host");
        }
        finally
        {
            File.Delete(blocker);
        }
    }

    [Fact]
    public async Task RunAsync_WithACaller_WritesTheCallerOnBothRecords()
    {
        // Arrange
        string caller = $"caller-{Guid.NewGuid():N}";
        EnableTiming(_timingDirectory);

        // Act
        await HostStartGate.RunAsync(() => Task.CompletedTask, caller).WaitAsync(WaitLimit);
        await HostStartGate.RunAsync(() => Task.CompletedTask).WaitAsync(WaitLimit);

        // Assert
        string?[] callers = ReadGateEntries().Select(entry => entry.GetProperty("caller").GetString()).ToArray();

        callers.Count(one => one == caller).Should().Be(
            2, "the named caller owns both its wait and its gated work, so a report can pick out its starts");
        callers.Count(one => one == HostStartGate.UnattributedCaller).Should().Be(
            2, "a caller that names nobody is labelled, so it never mixes with a stack start");
    }

    private static void EnableTiming(string directory)
    {
        Environment.SetEnvironmentVariable(TimingEnabledEnvironmentVariable, "1");
        Environment.SetEnvironmentVariable(TimingDirectoryEnvironmentVariable, directory);
    }

    private List<JsonElement> ReadGateEntries() => Directory
        .GetFiles(_timingDirectory, "fixture-timings-*.jsonl")
        .SelectMany(File.ReadAllLines)
        .Where(line => !string.IsNullOrWhiteSpace(line))
        .Select(line => JsonSerializer.Deserialize<JsonElement>(line))
        .Where(entry => entry.GetProperty("component").GetString() == nameof(HostStartGate))
        .ToList();
}
