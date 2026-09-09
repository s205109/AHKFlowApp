using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// The two lifecycle checks the design requires for several API hosts in one process.
/// </summary>
[Collection(ExclusiveTestCollection.Name)]
public sealed class HostStartGateTests
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
        ApiFactory second = new("AHKFlowApp.E2E.Tests.GateF");

        await first.StartAsync();
        await second.StartAsync();

        await first.DisposeAsync();

        using HttpClient client = second.CreateClient();
        HttpResponseMessage response = await client.GetAsync("/health");

        response.IsSuccessStatusCode.Should().BeTrue(
            "a stack must keep serving after another stack closes the shared Serilog logger");

        await second.DisposeAsync();
    }
}
