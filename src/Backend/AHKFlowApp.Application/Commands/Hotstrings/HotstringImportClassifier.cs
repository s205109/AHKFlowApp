using AHKFlowApp.Application.DTOs;

namespace AHKFlowApp.Application.Commands.Hotstrings;

/// <summary>
/// Assigns the <see cref="HotstringImportRowStatus.Duplicate"/> status the parser cannot:
/// a non-Invalid row is a duplicate when its trigger already exists for the owner
/// (<c>existingTriggers</c>) or repeats an earlier accepted row.
/// </summary>
internal static class HotstringImportClassifier
{
    public const string DuplicateReason = "A hotstring with this trigger already exists.";

    /// <summary>
    /// Marks import rows as duplicates based on existing triggers and within-batch collisions.
    /// </summary>
    /// <param name="rows">The hotstring import rows to classify.</param>
    /// <param name="existingTriggers">The set of triggers already existing for the owner. Must use a case-insensitive comparer.</param>
    /// <returns>The classified rows with duplicates marked.</returns>
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
