namespace AHKFlowApp.CLI.Exceptions;

internal sealed class ProfileNotFoundException(string profileName, string availableNames)
    : Exception($"Profile '{profileName}' not found. Available: {availableNames}");
