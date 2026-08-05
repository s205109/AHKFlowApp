using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>The outcome of one insert. On a refusal <see cref="Header"/> is the text unchanged.</summary>
public readonly record struct HeaderPresetInsertResult(bool Inserted, string Header, string? Error);

/// <summary>
/// Appends a header preset to a Profile header, wrapped in marker comments. This file owns the
/// marker format: the picker reads it to tell an owner a preset is already there, and an owner
/// reads it to find a block to delete by hand.
/// </summary>
public static class HeaderPresetInserter
{
    /// <summary>Mirrors ProfileRules.HeaderTemplateMaxLength on the server.</summary>
    public const int HeaderMaxLength = 8000;

    public static string OpenMarker(string id) => $"; --- AHKFlow preset: {id} ---";

    public static string CloseMarker(string id) => $"; --- end {id} ---";

    public static bool IsPresent(string? header, string id) =>
        (header ?? string.Empty).Contains(OpenMarker(id), StringComparison.Ordinal);

    /// <summary>
    /// Appends the preset. A header that does not end with a line break gets one first, so a
    /// marker never joins the owner's last line of code. The result ends with one line break,
    /// so the next insert behaves the same way.
    /// </summary>
    public static HeaderPresetInsertResult Insert(string? header, HeaderPresetDto preset)
    {
        string current = header ?? string.Empty;
        string block = $"{OpenMarker(preset.Id)}\n{preset.Body}\n{CloseMarker(preset.Id)}\n";

        string candidate = current.Length == 0
            ? block
            : current + (current.EndsWith('\n') ? string.Empty : "\n") + "\n" + block;

        if (candidate.Length > HeaderMaxLength)
        {
            int over = candidate.Length - HeaderMaxLength;
            return new(false, current,
                $"This preset does not fit. It would take the header {over} characters " +
                $"past the limit of {HeaderMaxLength}.");
        }

        return new(true, candidate, null);
    }
}
