using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Real API hosts started and stopped beside each other, the way the four stacks run.
/// </summary>
/// <remarks>
/// These tests set no process-wide environment variable, so they need no exclusive collection.
/// They run in their own collection, beside the four stacks. They only catch the Serilog race when
/// the timing happens to line up, so they confirm <see cref="HostStartGate"/> in the real host and
/// never stand in for the deterministic gate tests in <see cref="HostStartGateTests"/>.
/// </remarks>
[Collection(HostLifecycleTestCollection.Name)]
public sealed class HostLifecycleTests
{
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

/// <summary>
/// A parallel collection for tests that start their own API hosts and touch no process-wide state.
/// </summary>
[CollectionDefinition(Name)]
public sealed class HostLifecycleTestCollection
{
    public const string Name = "E2E-HostLifecycle";
}
