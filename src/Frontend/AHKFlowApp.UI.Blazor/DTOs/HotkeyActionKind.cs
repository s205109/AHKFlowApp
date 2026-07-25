namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>What a hotkey does. Mirror of the backend enum — order is the wire contract.</summary>
public enum HotkeyActionKind
{
    SendText = 0,
    SendKeys = 1,
    Run = 2,
    Window = 3,
    Remap = 4,
    Disable = 5,
    Raw = 6,
}
