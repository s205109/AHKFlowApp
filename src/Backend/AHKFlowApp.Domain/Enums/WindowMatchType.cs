namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// How a hotstring's window context value is matched against the active window
/// when generating AutoHotkey's <c>WinActive</c> expression.
/// </summary>
public enum WindowMatchType
{
    Executable = 0,
    WindowClass = 1,
    TitleContains = 2,
}
