namespace AHKFlowApp.Domain.Constants;

public static class DefaultProfileTemplates
{
    public const string Header = """
        #Requires AutoHotkey v2.0
        #SingleInstance Force
        SetCapsLockState "AlwaysOff"
        SetWorkingDir A_ScriptDir

        """;

    public const string Footer = "";
}
