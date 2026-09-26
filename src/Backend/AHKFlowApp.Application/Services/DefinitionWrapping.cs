using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Builds the lines around one generated definition: its Description comment lines above it, and
/// the <c>#HotIf</c> block of its Window context around it. It never writes a Runtime helper;
/// <see cref="RuntimeHelpers"/> does that.
/// </summary>
/// <remarks>
/// <see cref="AhkScriptGenerator"/> and both preview handlers call it, so a definition is wrapped
/// the same way in a Profile script and in its preview.
/// </remarks>
internal static class DefinitionWrapping
{
    // A bare "#HotIf" (no expression) clears the context of the #HotIf before it, so everything
    // written after it has global scope again.
    private const string HotIfClose = "#HotIf";

    /// <summary>
    /// The Description comment lines, then the definition. Each Description line becomes a
    /// <c>; </c> comment line. An empty or whitespace Description adds nothing.
    /// </summary>
    public static IEnumerable<string> WithDescription(string? description, string definition)
    {
        foreach (string line in DescriptionCommentLines(description))
            yield return line;

        yield return definition;
    }

    /// <summary>
    /// The given lines inside the <c>#HotIf</c> block of one Window context. Without a Window
    /// context, when <paramref name="matchType"/> is null, the lines come back unwrapped.
    /// </summary>
    public static IEnumerable<string> InWindowContext(
        WindowMatchType? matchType, string? value, IEnumerable<string> lines)
    {
        if (matchType is WindowMatchType type)
            yield return HotIfOpen(type, value!);

        foreach (string line in lines)
            yield return line;

        if (matchType is not null)
            yield return HotIfClose;
    }

    private static IEnumerable<string> DescriptionCommentLines(string? description)
    {
        if (string.IsNullOrWhiteSpace(description))
            yield break;

        foreach (string line in description.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
            yield return line.Length == 0 ? ";" : $"; {line}";
    }

    // ContextValue has already passed validation guaranteeing no double-quote, backtick, or
    // control characters (see WindowContextRules.AddWindowContextRules) — safe to embed raw here.
    private static string HotIfOpen(WindowMatchType matchType, string value)
    {
        string criterion = matchType switch
        {
            WindowMatchType.Executable => $"ahk_exe {value}",
            WindowMatchType.WindowClass => $"ahk_class {value}",
            WindowMatchType.TitleContains => value,
            _ => throw new InvalidOperationException($"Unsupported WindowMatchType: {matchType}"),
        };
        return $"#HotIf WinActive(\"{criterion}\")";
    }
}
