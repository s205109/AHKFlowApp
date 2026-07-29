namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// Where a known-shortcut record came from. Provenance, not a use: an owner who records a
/// Visual Studio shortcut produces an Owner record whose UsedBy is still "Visual Studio".
/// </summary>
public enum ShortcutRecordOrigin
{
    /// <summary>Shipped in the curated manifest.</summary>
    BuiltIn = 0,

    /// <summary>Recorded by the owner.</summary>
    Owner = 1,
}
