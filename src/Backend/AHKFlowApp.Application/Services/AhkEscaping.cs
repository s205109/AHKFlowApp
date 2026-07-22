namespace AHKFlowApp.Application.Services;

/// <summary>
/// AHK v2 string-literal escaping, shared by <see cref="HotstringEmitter"/> and
/// <c>HotkeyEmitter</c>. Used for the contents of a quoted literal —
/// <c>SendText "..."</c>, <c>Send "..."</c>, <c>Run("...")</c>.
/// </summary>
internal static class AhkEscaping
{
    /// <summary>
    /// Escapes a value for embedding inside an AHK v2 quoted string literal.
    /// </summary>
    /// <remarks>
    /// The backtick must be replaced <em>first</em>. Escaping it after the others would
    /// re-escape the backticks they just introduced, turning <c>`n</c> into <c>``n</c>.
    /// Note this differs from the hotstring <c>Escape</c> routine, which escapes <c>;</c>
    /// but not <c>"</c> — that one is for unquoted inline replacements, where a quote is
    /// just a character and a semicolon would start a comment.
    /// </remarks>
    public static string EscapeStringLiteral(string value) =>
        value
            .Replace("`", "``")
            .Replace("\"", "`\"")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t");
}
