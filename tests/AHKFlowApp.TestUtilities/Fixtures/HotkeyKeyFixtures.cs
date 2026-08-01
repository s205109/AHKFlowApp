using AHKFlowApp.Application.Constants;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// Registry-derived key lists, exposed publicly so test projects that cannot see the internal
/// <c>HotkeyKeys</c> registry can still assert against it.
/// </summary>
public static class HotkeyKeyFixtures
{
    /// <summary>
    /// Every canonical modifier key in the registry. Read by the frontend drift guard, so a
    /// modifier added to the registry cannot silently miss its notice label.
    /// </summary>
    public static IReadOnlyList<string> ModifierCanonicals { get; } =
    [
        .. HotkeyKeys.All
            .Where(e => e.Group == HotkeyKeys.GroupModifiers)
            .Select(e => e.Canonical),
    ];
}
