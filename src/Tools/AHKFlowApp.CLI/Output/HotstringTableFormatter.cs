using AHKFlowApp.CLI.Services;

namespace AHKFlowApp.CLI.Output;

public static class HotstringTableFormatter
{
    private const int TriggerWidth = 20;
    private const int KindWidth = 8;
    private const int ReplacementWidth = 40;
    private const int ProfilesWidth = 24;
    private const int ContextWidth = 22;
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
            Pad("Context", ContextWidth),
            Pad("Updated", UpdatedWidth)));
        writer.WriteLine(string.Join("  ",
            new string('-', TriggerWidth),
            new string('-', KindWidth),
            new string('-', ReplacementWidth),
            new string('-', ProfilesWidth),
            new string('-', ContextWidth),
            new string('-', UpdatedWidth)));

        foreach (HotstringDto dto in page.Items)
        {
            string updated = dto.UpdatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
            writer.WriteLine(string.Join("  ",
                Pad(Truncate(dto.Trigger, TriggerWidth), TriggerWidth),
                Pad(KindLabel(dto.Kind), KindWidth),
                Pad(FormatReplacementColumn(dto), ReplacementWidth),
                Pad(Truncate(FormatProfiles(dto, profileNamesById), ProfilesWidth), ProfilesWidth),
                Pad(Truncate(FormatContext(dto), ContextWidth), ContextWidth),
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

    private static string FormatContext(HotstringDto dto) => dto.ContextMatchType switch
    {
        WindowMatchType.Executable => $"exe:{dto.ContextValue}",
        WindowMatchType.WindowClass => $"class:{dto.ContextValue}",
        WindowMatchType.TitleContains => $"title:{dto.ContextValue}",
        _ => string.Empty,
    };

    private static string FormatReplacementColumn(HotstringDto dto)
    {
        // Raw rows show only the first line of the verbatim definition — Macro rows fall through
        // to the raw-replacement branch below unchanged, per the Phase 3 decision to keep Macro
        // display raw rather than adding a CLI-side token summary.
        if (dto.Kind == HotstringKind.Raw)
            return Truncate(FirstLine(dto.Replacement), ReplacementWidth);

        if (dto.Kind != HotstringKind.DateTime)
            return Truncate(dto.Replacement, ReplacementWidth);

        if (dto.DateTimeFormat is null)
            return Truncate("—", ReplacementWidth);

        if (dto.DateOffsetAmount is null || dto.DateOffsetUnit is null)
            return Truncate(dto.DateTimeFormat, ReplacementWidth);

        int amount = dto.DateOffsetAmount.Value;
        string sign = amount < 0 ? "-" : "+";
        string unitName = FormatUnitName(dto.DateOffsetUnit.Value, amount);
        string summary = $"{dto.DateTimeFormat} ({sign}{Math.Abs(amount)} {unitName})";
        return Truncate(summary, ReplacementWidth);
    }

    private static string FormatUnitName(DateOffsetUnit unit, int amount)
    {
        string name = unit.ToString().ToLowerInvariant();
        return Math.Abs(amount) == 1 ? name[..^1] : name;
    }

    private static string KindLabel(HotstringKind kind) => kind switch
    {
        HotstringKind.Text => "Text",
        HotstringKind.DateTime => "DateTime",
        HotstringKind.Macro => "Macro",
        HotstringKind.Raw => "Raw",
        _ => kind.ToString(),
    };

    private static string FirstLine(string s)
    {
        int newlineIndex = s.IndexOf('\n');
        return newlineIndex < 0 ? s : s[..newlineIndex];
    }

    private static string Truncate(string s, int max) =>
        s.Length <= max ? s : string.Concat(s.AsSpan(0, max - 1), "…");

    private static string Pad(string s, int width) =>
        s.Length >= width ? s : s + new string(' ', width - s.Length);
}
