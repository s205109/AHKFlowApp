using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator(
    HeaderTokenRenderer renderer,
    TimeProvider clock,
    IAppVersionProvider versions)
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

        var hsList = hotstrings.OrderBy(h => h.Trigger, StringComparer.Ordinal).ToList();
        var hkList = hotkeys.OrderBy(h => h.Description, StringComparer.Ordinal).ToList();

        HeaderTokenRenderer.Context ctx = new(
            ProfileName: profile.Name,
            AppVersion: versions.GetVersion(),
            HotstringCount: hsList.Count,
            HotkeyCount: hkList.Count,
            GeneratedAt: clock.GetUtcNow());

        List<string> lines = [renderer.Render(profile.HeaderTemplate, ctx), HotstringsSection];

        foreach (Hotstring hs in hsList)
            lines.Add(FormatHotstring(hs));

        lines.Add(HotkeysSection);

        foreach (Hotkey hk in hkList)
            lines.Add(FormatHotkey(hk));

        lines.Add(renderer.Render(profile.FooterTemplate, ctx));

        return string.Join("\n", lines);
    }

    private static string FormatHotstring(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        return $":{options}:{hs.Trigger}::{hs.Replacement}";
    }

    private static string FormatHotkey(Hotkey hk)
    {
        string prefix = "";
        if (hk.Ctrl) prefix += "^";
        if (hk.Alt) prefix += "!";
        if (hk.Shift) prefix += "+";
        if (hk.Win) prefix += "#";

        string fn = hk.Action switch
        {
            HotkeyAction.Send => "Send",
            HotkeyAction.Run => "Run",
            _ => throw new InvalidOperationException($"Unsupported HotkeyAction: {hk.Action}"),
        };

        return $"{prefix}{hk.Key}::{fn}(\"{hk.Parameters}\")";
    }
}
