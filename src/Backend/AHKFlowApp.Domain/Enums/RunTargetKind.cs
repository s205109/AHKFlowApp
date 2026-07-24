namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// Label for a <see cref="HotkeyActionKind.Run"/> target. Display-only: all three kinds emit the
/// same <c>Run("&lt;escaped&gt;")</c>, so the label carries no emission behavior (spec §8).
/// </summary>
public enum RunTargetKind
{
    /// <summary>An application or command line.</summary>
    Application = 0,

    /// <summary>A URL (<c>http://</c> / <c>https://</c>).</summary>
    Url = 1,

    /// <summary>A filesystem folder.</summary>
    Folder = 2,
}
