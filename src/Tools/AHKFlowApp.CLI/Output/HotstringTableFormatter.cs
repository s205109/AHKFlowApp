using AHKFlowApp.CLI.Services;

namespace AHKFlowApp.CLI.Output;

public static class HotstringTableFormatter
{
    private const int TriggerWidth = 20;
    private const int KindWidth = 8;
    private const int ReplacementWidth = 40;
    private const int ProfilesWidth = 24;
    private const int UpdatedWidth = 19;

    public static void Write(
        TextWriter writer,
        PagedList<HotstringDto> page,
        IReadOnlyDictionary<Guid, string> profileNamesById)
    {
        if (page.Items.Count == 0)
        {
            writer.WriteLine("No hotstrings found.");
            return;
        }

        writer.WriteLine(string.Join("  ",
            Pad("Trigger", TriggerWidth),
            Pad("Kind", KindWidth),
            Pad("Replacement", ReplacementWidth),
            Pad("Profiles", ProfilesWidth),
            Pad("Updated", UpdatedWidth)));
        writer.WriteLine(string.Join("  ",
            new string('-', TriggerWidth),
            new string('-', KindWidth),
            new string('-', ReplacementWidth),
            new string('-', ProfilesWidth),
            new string('-', UpdatedWidth)));

        foreach (HotstringDto dto in page.Items)
        {
            string updated = dto.UpdatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
            writer.WriteLine(string.Join("  ",
                Pad(Truncate(dto.Trigger, TriggerWidth), TriggerWidth),
                Pad(KindLabel(dto.Kind), KindWidth),
                Pad(Truncate(dto.Replacement, ReplacementWidth), ReplacementWidth),
                Pad(Truncate(FormatProfiles(dto, profileNamesById), ProfilesWidth), ProfilesWidth),
                updated));
        }

        if (page.TotalPages > 1)
        {
            writer.WriteLine();
            writer.WriteLine(
                $"Page {page.Page}/{page.TotalPages} (showing {page.Items.Count} of {page.TotalCount}) — use --page N for next");
        }
    }

    private static string FormatProfiles(HotstringDto dto, IReadOnlyDictionary<Guid, string> names)
    {
        if (dto.AppliesToAllProfiles) return "all";
        if (dto.ProfileIds.Length == 0) return "all";

        List<string> resolved = [];
        int unresolved = 0;
        foreach (Guid id in dto.ProfileIds)
        {
            if (names.TryGetValue(id, out string? name)) resolved.Add(name);
            else unresolved++;
        }

        if (resolved.Count == 0) return $"{dto.ProfileIds.Length} profiles";

        string head = string.Join(", ", resolved.Take(3));
        int more = Math.Max(0, resolved.Count - 3) + unresolved;
        return more > 0 ? $"{head} +{more} more" : head;
    }

    private static string KindLabel(HotstringKind kind) => kind switch
    {
        HotstringKind.Text => "Text",
        HotstringKind.DateTime => "DateTime",
        HotstringKind.Macro => "Macro",
        HotstringKind.Script => "Script",
        _ => kind.ToString(),
    };

    private static string Truncate(string s, int max) =>
        s.Length <= max ? s : string.Concat(s.AsSpan(0, max - 1), "…");

    private static string Pad(string s, int width) =>
        s.Length >= width ? s : s + new string(' ', width - s.Length);
}
