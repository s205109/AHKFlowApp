namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>
/// Routes server validation messages to the inputs they belong next to. A sibling of
/// <see cref="ApiErrorMessageFactory"/>: that one builds one message string for a generic alert,
/// this one fills a per-field dictionary an edit dialog reads from.
/// </summary>
internal static class FieldErrorMapper
{
    /// <summary>
    /// Maps a ProblemDetails validation dictionary onto field names, replacing whatever
    /// <paramref name="target"/> held before. Property paths arrive as e.g. "Input.RunTarget" —
    /// the last dotted part is the field. Anything that maps to no known field is returned
    /// instead of being silently dropped, so the caller can show it in a generic alert.
    /// </summary>
    /// <param name="errors">The server's validation dictionary.</param>
    /// <param name="knownFields">
    /// Field names that have an input to show a message on. Build it with
    /// <see cref="StringComparer.OrdinalIgnoreCase"/> — the server may spell a path in a
    /// different case than the model property.
    /// </param>
    /// <param name="target">
    /// Receives one message per known field. Build it with
    /// <see cref="StringComparer.OrdinalIgnoreCase"/> for the same reason.
    /// </param>
    /// <returns>The first message that mapped to no known field, or null.</returns>
    public static string? Map(
        IReadOnlyDictionary<string, string[]> errors,
        IReadOnlySet<string> knownFields,
        Dictionary<string, string> target)
    {
        target.Clear();
        List<string> unmapped = [];

        foreach ((string key, string[] messages) in errors)
        {
            if (messages.FirstOrDefault() is not { } message)
                continue;

            string field = key[(key.LastIndexOf('.') + 1)..];
            if (knownFields.Contains(field))
                target.TryAdd(field, message);
            else
                unmapped.Add(message);
        }

        return unmapped.FirstOrDefault();
    }
}
