namespace AHKFlowApp.Domain.Enums;

/// <summary>
/// How hard it is for a script to take a key combination over. One axis only — which product
/// uses the keys is carried by the use's UsedBy label, not by this enum. Not named Category or
/// Kind: CONTEXT.md already gives both of those words other meanings.
/// </summary>
public enum ShortcutProtection
{
    /// <summary>Windows handles the keys before any hook can see them. Needs a pinned Microsoft source.</summary>
    Protected = 0,

    /// <summary>Something uses it, and a script may or may not take it over.</summary>
    Normal = 1,

    /// <summary>Recorded by an owner with no claim about how hard the keys are to take.</summary>
    Unknown = 2,
}
