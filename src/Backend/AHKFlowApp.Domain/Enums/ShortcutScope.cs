namespace AHKFlowApp.Domain.Enums;

/// <summary>Whether a shortcut use fires anywhere, or only while its application is in front.</summary>
public enum ShortcutScope
{
    /// <summary>Fires anywhere, whatever window has focus.</summary>
    Global = 0,

    /// <summary>Fires only while the application that owns it is in front.</summary>
    Foreground = 1,
}
