using AHKFlowApp.CLI.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class ConsoleErrorDeviceCodePromptWriterTests
{
    [Fact]
    public async Task WriteAsync_WritesVerificationUrlAndUserCodeToError()
    {
        using StringWriter stderr = new();
        var sut = new ConsoleErrorDeviceCodePromptWriter(() => stderr);

        await sut.WriteAsync(
            new DeviceCodePrompt(
                "https://microsoft.com/devicelogin",
                "ABC-123",
                "Open the page and enter the code."),
            CancellationToken.None);

        string output = stderr.ToString();
        output.Should().Contain("https://microsoft.com/devicelogin");
        output.Should().Contain("ABC-123");
        output.Should().Contain("Open the page and enter the code.");
    }
}
