using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class ConsoleErrorHttpRetryStatusWriterTests
{
    [Fact]
    public void WriteRetrying_WritesFriendlyRetryMessage()
    {
        StringWriter stderr = new();
        ConsoleErrorHttpRetryStatusWriter writer = new(() => stderr);

        writer.WriteRetrying("hotstrings", 2, 5, TimeSpan.FromSeconds(2));

        stderr.ToString().Should().Contain(
            "The API may be cold-starting. Retrying hotstrings request (2/5) in 2s...");
    }
}
