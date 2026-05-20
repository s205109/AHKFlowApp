namespace AHKFlowApp.Domain.Constants;

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
