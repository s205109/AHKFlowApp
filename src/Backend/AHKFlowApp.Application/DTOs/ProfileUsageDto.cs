namespace AHKFlowApp.Application.DTOs;

/// <summary>
/// The items a delete of one profile would leave applying to no profile.
/// An item counts only when this profile is its one and only profile.
/// An item set to apply to all profiles never counts.
/// </summary>
/// <param name="HotstringsLeftWithNoProfile">Number of hotstrings that link to this profile alone.</param>
/// <param name="HotkeysLeftWithNoProfile">Number of hotkeys that link to this profile alone.</param>
public sealed record ProfileUsageDto(
    int HotstringsLeftWithNoProfile,
    int HotkeysLeftWithNoProfile);
