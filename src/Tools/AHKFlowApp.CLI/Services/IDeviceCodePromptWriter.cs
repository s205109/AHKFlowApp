namespace AHKFlowApp.CLI.Services;

public interface IDeviceCodePromptWriter
{
    Task WriteAsync(DeviceCodePrompt prompt, CancellationToken ct);
}
