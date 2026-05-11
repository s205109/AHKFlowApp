namespace AHKFlowApp.CLI.Services;

public sealed class ConsoleErrorDeviceCodePromptWriter(Func<TextWriter>? errorFactory = null)
    : IDeviceCodePromptWriter
{
    private readonly Func<TextWriter> _errorFactory = errorFactory ?? (() => Console.Error);

    public async Task WriteAsync(DeviceCodePrompt prompt, CancellationToken ct)
    {
        TextWriter stderr = _errorFactory();
        await stderr.WriteLineAsync(prompt.Message);
        await stderr.WriteLineAsync($"Verification URL: {prompt.VerificationUrl}");
        await stderr.WriteLineAsync($"Code: {prompt.UserCode}");
    }
}
