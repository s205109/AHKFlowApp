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
public sealed class HostStartGateTests
{
    private static readonly TimeSpan WaitLimit = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan SettleTime = TimeSpan.FromMilliseconds(250);

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
}
