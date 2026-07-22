namespace AHKFlowApp.Domain.Enums;

/// <summary>Operation a <see cref="HotkeyActionKind.Window"/> hotkey performs on the active window.</summary>
public enum WindowOp
{
    /// <summary><c>WinMinimize("A")</c>.</summary>
    Minimize = 0,

    /// <summary><c>WinMaximize("A")</c>.</summary>
    Maximize = 1,

    /// <summary><c>WinRestore("A")</c>.</summary>
    Restore = 2,

    /// <summary><c>WinClose("A")</c>.</summary>
    Close = 3,

    /// <summary><c>WinSetAlwaysOnTop(-1, "A")</c>.</summary>
    ToggleAlwaysOnTop = 4,
}
