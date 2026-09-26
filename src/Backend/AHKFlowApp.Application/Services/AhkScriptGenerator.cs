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
        lines.AddRange(RuntimeHelpers.NeededBy(hsList, hkList));
        lines.Add(HotstringsSection);

        EmitContextGroups(
            lines,
            hsList,
            h => (h.ContextMatchType, h.ContextValue),
            hs => DefinitionWrapping.WithDescription(hs.Description, HotstringEmitter.Emit(hs)));

        lines.Add(HotkeysSection);

        EmitContextGroups(
            lines,
            hkList,
            h => (h.ContextMatchType, h.ContextValue),
            hk => DefinitionWrapping.WithDescription(hk.Description, HotkeyEmitter.Emit(hk)));

        lines.Add(renderer.Render(profile.FooterTemplate, ctx));

        return string.Join("\n", lines);
    }

    /// <summary>
    /// Groups entries by window context (both parts null means global) and appends them to
    /// <paramref name="lines"/>. Context groups come first, ordered by match type then by value.
    /// <see cref="DefinitionWrapping.InWindowContext"/> wraps each context group in
    /// <c>#HotIf WinActive(...)</c> and closes it with a bare <c>#HotIf</c>. The global group comes last and stays unwrapped. Every group closes before
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
        Func<T, IEnumerable<string>> linesOf)
    {
        List<IGrouping<(WindowMatchType? MatchType, string? Value), T>> groups =
            [.. ordered.GroupBy(contextOf)];

        IEnumerable<IGrouping<(WindowMatchType? MatchType, string? Value), T>> contextGroups = groups
            .Where(g => g.Key.MatchType is not null)
            .OrderBy(g => (int)g.Key.MatchType!.Value)
            .ThenBy(g => g.Key.Value, StringComparer.Ordinal);

        foreach (IGrouping<(WindowMatchType? MatchType, string? Value), T> group in contextGroups)
            lines.AddRange(DefinitionWrapping.InWindowContext(
                group.Key.MatchType, group.Key.Value, group.SelectMany(linesOf)));

        IGrouping<(WindowMatchType? MatchType, string? Value), T>? globalGroup =
            groups.FirstOrDefault(g => g.Key.MatchType is null);

        if (globalGroup is not null)
            lines.AddRange(globalGroup.SelectMany(linesOf));
    }
}
