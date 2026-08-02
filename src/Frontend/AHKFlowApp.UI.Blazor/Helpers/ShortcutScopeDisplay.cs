using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>Where a known shortcut applies, in the words the pages show.</summary>
public static class ShortcutScopeDisplay
{
    public static string Label(ShortcutScope scope) =>
        scope == ShortcutScope.Global ? "Anywhere" : "Only in front";
}
