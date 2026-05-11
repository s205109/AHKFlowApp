namespace AHKFlowApp.CLI.Services;

public sealed record DeviceCodePrompt(
    string VerificationUrl,
    string UserCode,
    string Message);
