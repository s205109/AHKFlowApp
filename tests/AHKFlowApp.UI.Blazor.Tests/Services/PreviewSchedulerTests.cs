using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class PreviewSchedulerTests
{
    private static ApiResult<string> Ok(string value) => ApiResult<string>.Ok(value);

    [Fact]
    public async Task Schedule_Success_ReportsResultAndClearsPending()
    {
        TaskCompletionSource<ApiResult<string>> pending = new();
        List<ApiResult<string>> results = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (_, _) => pending.Task,
            onResult: results.Add,
            onUnexpectedError: (_, _) => { },
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        sut.Pending.Should().BeTrue("the fetch has not completed yet");

        pending.SetResult(Ok("snippet"));
        await pending.Task;
        await Task.Yield();

        results.Should().ContainSingle().Which.Value.Should().Be("snippet");
        sut.Pending.Should().BeFalse();
    }

    [Fact]
    public async Task Schedule_SupersededResponseCompletesLast_IsDiscarded()
    {
        // The first fetch ignores its cancellation token and completes successfully after the
        // second was scheduled. Only the generation check can discard it.
        TaskCompletionSource<ApiResult<string>> first = new();
        TaskCompletionSource<ApiResult<string>> second = new();
        List<ApiResult<string>> results = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (request, _) => request == 1 ? first.Task : second.Task,
            onResult: results.Add,
            onUnexpectedError: (_, _) => { },
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        sut.Schedule(2, TimeSpan.Zero);

        second.SetResult(Ok("second"));
        await second.Task;
        await Task.Yield();

        first.SetResult(Ok("first"));
        await first.Task;
        await Task.Yield();

        results.Should().ContainSingle().Which.Value.Should().Be("second");
    }

    [Fact]
    public async Task Cancel_ThenLateSuccess_IsDiscarded()
    {
        TaskCompletionSource<ApiResult<string>> pending = new();
        List<ApiResult<string>> results = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (_, _) => pending.Task,
            onResult: results.Add,
            onUnexpectedError: (_, _) => { },
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        sut.Cancel();
        sut.Pending.Should().BeFalse();

        pending.SetResult(Ok("late"));
        await pending.Task;
        await Task.Yield();

        results.Should().BeEmpty();
    }

    [Fact]
    public async Task Schedule_UnexpectedException_ReportsAsCurrent()
    {
        List<(Exception Error, bool IsCurrent)> failures = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (_, _) => throw new InvalidOperationException("boom"),
            onResult: _ => { },
            onUnexpectedError: (error, isCurrent) => failures.Add((error, isCurrent)),
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        await Task.Yield();

        failures.Should().ContainSingle();
        failures[0].Error.Should().BeOfType<InvalidOperationException>();
        failures[0].IsCurrent.Should().BeTrue();
        sut.Pending.Should().BeFalse("a failed preview must not leave the spinner running");
    }

    [Fact]
    public async Task Schedule_UnexpectedExceptionAfterSupersede_ReportsAsNotCurrent()
    {
        // The caller still logs a superseded failure, but must not overwrite the newer state.
        TaskCompletionSource<ApiResult<string>> first = new();
        List<(Exception Error, bool IsCurrent)> failures = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (request, _) => request == 1
                ? first.Task
                : Task.FromResult(Ok("second")),
            onResult: _ => { },
            onUnexpectedError: (error, isCurrent) => failures.Add((error, isCurrent)),
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        sut.Schedule(2, TimeSpan.Zero);

        first.SetException(new InvalidOperationException("boom"));
        await Task.Yield();
        await Task.Yield();

        failures.Should().ContainSingle();
        failures[0].IsCurrent.Should().BeFalse();
    }

    [Fact]
    public async Task Schedule_CancelledThroughItsOwnToken_IsSilent()
    {
        // The scheduler's own token is what a supersede, a collapsed panel or a disposed dialog
        // cancels. Only that is a real cancellation, and only that is silent.
        List<(Exception Error, bool IsCurrent)> failures = [];
        List<ApiResult<string>> results = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: async (_, ct) =>
            {
                await Task.Delay(Timeout.Infinite, ct);
                return Ok("never reached");
            },
            onResult: results.Add,
            onUnexpectedError: (error, isCurrent) => failures.Add((error, isCurrent)),
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        sut.Cancel();
        await Task.Yield();

        failures.Should().BeEmpty("a cancelled preview is never surfaced as an error");
        results.Should().BeEmpty();
    }

    [Fact]
    public async Task Schedule_HttpTimeout_ClearsPendingAndReportsTheFailure()
    {
        // HttpClient's own timeout throws TaskCanceledException, which is an
        // OperationCanceledException — but nothing asked this preview to stop, so its token is
        // not cancelled. Treating it as a user cancellation would leave the spinner running, the
        // snippet dimmed and the copy button disabled with no way back.
        List<(Exception Error, bool IsCurrent)> failures = [];
        int renders = 0;
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (_, _) => Task.FromCanceled<ApiResult<string>>(
                new CancellationToken(canceled: true)),
            onResult: _ => { },
            onUnexpectedError: (error, isCurrent) => failures.Add((error, isCurrent)),
            stateHasChanged: () => renders++);

        sut.Schedule(1, TimeSpan.Zero);
        await Task.Yield();

        sut.Pending.Should().BeFalse("a timed-out preview must not leave the spinner running");
        failures.Should().ContainSingle();
        failures[0].IsCurrent.Should().BeTrue();
        renders.Should().BeGreaterThan(1, "the cleared spinner has to reach the screen");
    }

    [Fact]
    public async Task Schedule_WithDebounce_DoesNotFetchBeforeTheDelayElapses()
    {
        int fetches = 0;
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (_, _) => { fetches++; return Task.FromResult(Ok("snippet")); },
            onResult: _ => { },
            onUnexpectedError: (_, _) => { },
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.FromMilliseconds(500));
        await Task.Yield();

        fetches.Should().Be(0, "the debounce delay has not elapsed");
    }

    [Fact]
    public async Task Dispose_ThenLateSuccess_IsDiscarded()
    {
        TaskCompletionSource<ApiResult<string>> pending = new();
        List<ApiResult<string>> results = [];
        PreviewScheduler<int, string> sut = new(
            fetchAsync: (_, _) => pending.Task,
            onResult: results.Add,
            onUnexpectedError: (_, _) => { },
            stateHasChanged: () => { });

        sut.Schedule(1, TimeSpan.Zero);
        sut.Dispose();

        pending.SetResult(Ok("late"));
        await pending.Task;
        await Task.Yield();

        results.Should().BeEmpty();
    }
}
