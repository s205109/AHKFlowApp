using System;

namespace AHKFlowApp.Domain.Enums;

public enum HotstringKind
{
    Text = 0,
    DateTime = 1,
    Macro = 2,

    /// <summary>
    /// Retired legacy kind. Accepted only when deserializing stored history snapshots,
    /// never in new payloads — validators reject it and restore/revert convert it to
    /// <see cref="Raw"/> via the shared Script→Raw composer. The value is kept so
    /// historical snapshots with <c>Kind = 3</c> still deserialize; reusing it for a new
    /// meaning would not be wire- or history-compatible.
    /// </summary>
    [Obsolete("Legacy; accepted only when deserializing history snapshots. Use Raw for new definitions.")]
    Script = 3,

    /// <summary>
    /// Raw AHK v2 hotstring definition stored verbatim in <c>Replacement</c> (first line
    /// <c>:options:trigger::</c>, optional brace body). The trigger is derived server-side;
    /// option-flag columns are ignored. Replaces the legacy <see cref="Script"/> kind.
    /// </summary>
    Raw = 4,
}
