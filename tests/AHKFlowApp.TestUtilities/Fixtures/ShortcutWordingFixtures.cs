using AHKFlowApp.Application.Constants;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// The shortcut wording rule, exposed publicly so test projects that cannot see the internal
/// <c>ShortcutWording</c> rule can still assert against it.
/// </summary>
public static class ShortcutWordingFixtures
{
    /// <summary>
    /// True if the text makes a claim about what will or will not happen. Forwards to the rule the
    /// app enforces, so a frontend test cannot keep a narrower copy of it.
    /// </summary>
    public static bool MakesAbsoluteClaim(string text) => ShortcutWording.MakesAbsoluteClaim(text);
}
