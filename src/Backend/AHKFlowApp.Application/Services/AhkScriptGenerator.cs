using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

public sealed class AhkScriptGenerator(
    HeaderTokenRenderer renderer,
    TimeProvider clock,
    IAppVersionProvider appVersionProvider)
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
            AppVersion: appVersionProvider.GetVersion(),
            HotstringCount: hsList.Count,
            HotkeyCount: hkList.Count,
            GeneratedAt: clock.GetUtcNow());

        List<string> lines = [renderer.Render(profile.HeaderTemplate, ctx), HotstringsSection];

        // Group by window context (both-null = global). GroupBy is stable, so the
        // trigger-ordinal pre-sort above survives within each group. Context groups are
        // wrapped in #HotIf WinActive(...) / #HotIf and emitted first, ordered by match
        // type then value; the global group is emitted last, unwrapped.
        List<IGrouping<(WindowMatchType? MatchType, string? Value), Hotstring>> groups =
            [.. hsList.GroupBy(h => (h.ContextMatchType, h.ContextValue))];

        IEnumerable<IGrouping<(WindowMatchType? MatchType, string? Value), Hotstring>> contextGroups = groups
            .Where(g => g.Key.MatchType is not null)
            .OrderBy(g => (int)g.Key.MatchType!.Value)
            .ThenBy(g => g.Key.Value, StringComparer.Ordinal);

        foreach (IGrouping<(WindowMatchType? MatchType, string? Value), Hotstring> group in contextGroups)
        {
            lines.Add(HotstringEmitter.EmitHotIfOpen(group.Key.MatchType!.Value, group.Key.Value!));
            foreach (Hotstring hs in group)
            {
                lines.AddRange(HotstringEmitter.DescriptionCommentLines(hs.Description));
                lines.Add(HotstringEmitter.Emit(hs));
            }
            lines.Add(HotstringEmitter.HotIfClose);
        }

        IGrouping<(WindowMatchType? MatchType, string? Value), Hotstring>? globalGroup =
            groups.FirstOrDefault(g => g.Key.MatchType is null);

        if (globalGroup is not null)
            foreach (Hotstring hs in globalGroup)
            {
                lines.AddRange(HotstringEmitter.DescriptionCommentLines(hs.Description));
                lines.Add(HotstringEmitter.Emit(hs));
            }

        lines.Add(HotkeysSection);

        foreach (Hotkey hk in hkList)
        {
            lines.AddRange(HotstringEmitter.DescriptionCommentLines(hk.Description));
            lines.Add(FormatHotkey(hk));
        }

        lines.Add(renderer.Render(profile.FooterTemplate, ctx));

        return string.Join("\n", lines);
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
