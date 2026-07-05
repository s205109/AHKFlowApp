using AHKFlowApp.Application.DTOs;

namespace AHKFlowApp.Application.Commands.Hotstrings;

#pragma warning disable CS1734
/// <summary>
/// Assigns the <see cref="HotstringImportRowStatus.Duplicate"/> status the parser cannot:
/// a non-Invalid row is a duplicate when its trigger already exists for the owner
/// (<paramref name="existingTriggers"/>) or repeats an earlier accepted row.
/// </summary>
#pragma warning restore CS1734
internal static class HotstringImportClassifier
{
    public const string DuplicateReason = "A hotstring with this trigger already exists.";

    public static IReadOnlyList<HotstringImportRowDto> MarkDuplicates(
        IReadOnlyList<HotstringImportRowDto> rows,
        IReadOnlySet<string> existingTriggers)
    {
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        List<HotstringImportRowDto> result = new(rows.Count);

        foreach (HotstringImportRowDto row in rows)
        {
            if (row.Status == HotstringImportRowStatus.Invalid)
            {
                result.Add(row);
                continue;
            }

            bool duplicate = existingTriggers.Contains(row.Trigger) || !seen.Add(row.Trigger);
            result.Add(duplicate
                ? row with { Status = HotstringImportRowStatus.Duplicate, Reason = DuplicateReason }
                : row);
        }

        return result;
    }
}
