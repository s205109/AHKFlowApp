using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator
{
    private const string HotstringsSection = "; --- Hotstrings ---";
    private const string HotkeysSection = "; --- Hotkeys ---";

    public string Generate(
        Profile profile,
        IEnumerable<Hotstring> hotstrings,
        IEnumerable<Hotkey> hotkeys)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(hotstrings);
        ArgumentNullException.ThrowIfNull(hotkeys);

        List<string> lines = [profile.HeaderTemplate, HotstringsSection];

        foreach (Hotstring hs in hotstrings)
            lines.Add(FormatHotstring(hs));

        lines.Add(HotkeysSection);
        lines.Add(profile.FooterTemplate);

        return string.Join("\n", lines);
    }

    private static string FormatHotstring(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        return $":{options}:{hs.Trigger}::{hs.Replacement}";
    }
}
