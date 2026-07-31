using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Commands.Hotkeys;

/// <summary>
/// Shared duplicate-combination conflict message for hotkey create, update, restore, and revert
/// handlers. The composite unique index allows the same key + modifier combination to exist once
/// globally and once per distinct window context, so the message names the window that clashed.
/// A hotkey clash is hard to find by hand, which is why this says more than the hotstring version.
/// </summary>
internal static class HotkeyConflictMessages
{
    private const string Prefix = "A hotkey with this key + modifier combination already exists";

    /// <summary>
    /// Builds the message for the context that clashed. The value is safe to quote: the validator
    /// rejects double-quote characters in <c>ContextValue</c>, so it can never close the quote early.
    /// </summary>
    public static string Duplicate(WindowMatchType? matchType, string? value) => matchType switch
    {
        null => $"{Prefix} for all windows.",
        WindowMatchType.Executable => $"{Prefix} for \"{value}\".",
        WindowMatchType.WindowClass => $"{Prefix} for the window class \"{value}\".",
        WindowMatchType.TitleContains => $"{Prefix} for windows with \"{value}\" in the title.",
        _ => $"{Prefix} in the same window context.",
    };
}
