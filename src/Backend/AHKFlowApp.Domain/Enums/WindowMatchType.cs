namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// How the window context value of a hotstring or a hotkey is matched against the active window
/// when generating AutoHotkey's <c>WinActive</c> expression.
/// </summary>
public enum WindowMatchType
{
    Executable = 0,
    WindowClass = 1,
    TitleContains = 2,
}
