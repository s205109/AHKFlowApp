namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>Window operation a Window-kind hotkey performs. Mirror of the backend enum.</summary>
public enum WindowOp
{
    Minimize = 0,
    Maximize = 1,
    Restore = 2,
    Close = 3,
    ToggleAlwaysOnTop = 4,
}
