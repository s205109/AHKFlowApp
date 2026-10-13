namespace AHKFlowApp.UI.Blazor.Constants;

/// <summary>
/// The Blazor project references no backend project, so this is a hand-kept copy of
/// <c>AHKFlowApp.Domain.Constants.DefaultProfileTemplates</c>. The web UI needs the text in the
/// browser: a new profile's form starts from it, so the owner sees what they will get and can
/// edit or clear it. <c>DefaultProfileTemplatesParityTests</c> fails the build when the two
/// copies differ.
/// </summary>
public static class DefaultProfileTemplates
{
    public const string Header = """
        ; {ProfileName} — AHKFlowApp v{AppVersion}
        ; {HotstringCount} hotstrings, {HotkeyCount} hotkeys
        ; Generated {GeneratedAt:yyyy-MM-dd HH:mm}Z

        #Requires AutoHotkey v2.0
        #SingleInstance Force
        #Warn All, Off
        SendMode "Input"
        SetWorkingDir A_ScriptDir
        SetTitleMatchMode 2

        """;

    public const string Footer = "";
}
