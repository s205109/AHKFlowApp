namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// What a hotkey does when it fires. Replaces the two-value <see cref="HotkeyAction"/>.
/// </summary>
/// <remarks>
/// Values are natural and unrelated to legacy <see cref="HotkeyAction"/> ints on purpose: the
/// legacy-to-typed converter keys off the presence of the legacy snapshot members, never their
/// numeric value, so a stale <c>Action = 1</c> can never masquerade as a valid new kind (spec §8).
/// </remarks>
public enum HotkeyActionKind
{
    /// <summary>Type literal text (<c>SendText("...")</c>). Free text, escaped at emission.</summary>
    SendText = 0,

    /// <summary>Send a validated key token (<c>Send("{Volume_Up}")</c>).</summary>
    SendKeys = 1,

    /// <summary>Launch an application, URL, or folder (<c>Run("...")</c>). Free text, escaped.</summary>
    Run = 2,

    /// <summary>Operate on the active window (<c>WinMinimize("A")</c>, …).</summary>
    Window = 3,

    /// <summary>Make one key behave as another (<c>origin::dest</c>).</summary>
    Remap = 4,

    /// <summary>Disable a key (<c>key::return</c>).</summary>
    Disable = 5,

    /// <summary>
    /// Verbatim action body, emitted as <c>origin::&lt;body&gt;</c> with no wrapper — a block body
    /// carries its own braces. The sole path whose contents AHK never sees validated for meaning;
    /// only shape is checked (brace balance, no <c>#</c> directive, length).
    /// </summary>
    Raw = 6,
}
