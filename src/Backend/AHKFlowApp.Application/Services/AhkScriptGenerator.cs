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

        List<string> lines = [renderer.Render(profile.HeaderTemplate, ctx)];
        if (hsList.Any(h => HotstringEmitter.ResolveEffectiveDelivery(h) == HotstringDelivery.ClipboardPaste))
            lines.Add(HotstringEmitter.PasteHelperFunction);
        lines.Add(HotstringsSection);

        EmitContextGroups(
            lines,
            hsList,
            h => (h.ContextMatchType, h.ContextValue),
            (target, hs) =>
            {
                target.AddRange(HotstringEmitter.DescriptionCommentLines(hs.Description));
                target.Add(HotstringEmitter.Emit(hs));
            });

        lines.Add(HotkeysSection);

        EmitContextGroups(
            lines,
            hkList,
            h => (h.ContextMatchType, h.ContextValue),
            (target, hk) =>
            {
                target.AddRange(HotstringEmitter.DescriptionCommentLines(hk.Description));
                target.Add(HotkeyEmitter.Emit(hk));
            });

        lines.Add(renderer.Render(profile.FooterTemplate, ctx));

        return string.Join("\n", lines);
    }

    /// <summary>
    /// Groups entries by window context (both parts null means global) and appends them to
    /// <paramref name="lines"/>. Context groups come first, wrapped in
    /// <c>#HotIf WinActive(...)</c> and closed with a bare <c>#HotIf</c>, ordered by match type
    /// then by value. The global group comes last and stays unwrapped. Every group closes before
    /// the next one opens, so no context can leak into the entries that follow.
    /// </summary>
    /// <remarks>
    /// <c>GroupBy</c> is stable, so the caller's pre-sort survives inside each group. Hotstrings
    /// and hotkeys share this method because AHK's <c>#HotIf</c> applies to both.
    /// </remarks>
    private static void EmitContextGroups<T>(
        List<string> lines,
        List<T> ordered,
        Func<T, (WindowMatchType? MatchType, string? Value)> contextOf,
        Action<List<string>, T> emitOne)
    {
        List<IGrouping<(WindowMatchType? MatchType, string? Value), T>> groups =
            [.. ordered.GroupBy(contextOf)];

        IEnumerable<IGrouping<(WindowMatchType? MatchType, string? Value), T>> contextGroups = groups
            .Where(g => g.Key.MatchType is not null)
            .OrderBy(g => (int)g.Key.MatchType!.Value)
            .ThenBy(g => g.Key.Value, StringComparer.Ordinal);

        foreach (IGrouping<(WindowMatchType? MatchType, string? Value), T> group in contextGroups)
        {
            lines.Add(HotstringEmitter.EmitHotIfOpen(group.Key.MatchType!.Value, group.Key.Value!));
            foreach (T item in group)
                emitOne(lines, item);
            lines.Add(HotstringEmitter.HotIfClose);
        }

        IGrouping<(WindowMatchType? MatchType, string? Value), T>? globalGroup =
            groups.FirstOrDefault(g => g.Key.MatchType is null);

        if (globalGroup is not null)
            foreach (T item in globalGroup)
                emitOne(lines, item);
    }
}
