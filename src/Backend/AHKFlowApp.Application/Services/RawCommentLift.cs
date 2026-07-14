namespace AHKFlowApp.Application.Services;

/// <summary>
/// Merge policy for a comment lifted off a pasted Raw definition into the hotstring's Description.
/// Single source of truth shared by the Raw validator (length check) and the Create/Update
/// handlers (persisted value) so they can never disagree. No data loss: an existing Description is
/// never overwritten — the lifted comment is appended unless it is empty or an exact duplicate.
/// </summary>
internal static class RawCommentLift
{
    /// <summary>
    /// Merges <paramref name="lifted"/> into <paramref name="description"/>:
    /// empty Description → the lifted comment; equal → the Description unchanged (duplicate dropped);
    /// otherwise the lifted comment appended on a new line. Returns null when both are empty.
    /// </summary>
    public static string? Merge(string? description, string? lifted)
    {
        string? desc = string.IsNullOrWhiteSpace(description) ? null : description.Trim();
        string? lift = string.IsNullOrWhiteSpace(lifted) ? null : lifted;

        if (lift is null)
            return desc;
        if (desc is null)
            return lift;
        if (string.Equals(desc, lift, StringComparison.Ordinal))
            return desc;

        return $"{desc}\n{lift}";
    }
}
